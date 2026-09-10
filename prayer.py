#!/usr/bin/env python3
"""Salah's provider boundary. Standard library only; no desktop imports."""
import argparse
import concurrent.futures
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
from datetime import date, datetime, time, timedelta, timezone
from email.utils import parsedate_to_datetime
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

ORDER = ('Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha')
DEFAULTS = {
    'version': 1, 'provider': 'aladhan', 'locationMode': 'auto', 'city': '', 'country': '',
    'latitude': None, 'longitude': None, 'timezone': '', 'method': 3, 'school': 0,
    'language': 'en', 'beforeMinutes': 30, 'afterMinutes': 30,
    'notifications': True, 'sound': 'off', 'soundFile': '', 'volume': 0.35,
    'motion': True, 'countdown': False, 'clickOpensPanel': True, 'scheduleFile': '',
    'displayMode': 'earth', 'guidanceProfile': 'diyanet', 'showQibla': False, 'countdownWindow': 'both',
}


class PrayerError(Exception):
    def __init__(self, code, message, retry_after=None):
        super().__init__(message)
        self.code = code
        self.retry_after = retry_after

    def as_dict(self):
        result = {'error': str(self), 'code': self.code}
        if self.retry_after is not None:
            result['retryAfterSeconds'] = self.retry_after
        return result


def retry_after_seconds(value, now=None):
    """Read an HTTP Retry-After delay without sleeping in the fetch worker."""
    if not value:
        return None
    try:
        value = value.strip()
        if re.fullmatch(r'[0-9]+', value):
            delay = int(value)
        else:
            deadline = parsedate_to_datetime(value)
            delay = math.ceil((deadline - (now or datetime.now(timezone.utc))).total_seconds())
        # Reject unusable values; valid delays pass through to the desktop timer.
        return max(0, delay) if delay < 10**12 else None
    except (ValueError, TypeError, OverflowError):
        return None


def read_json(path, fallback):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        return fallback
    except (OSError, ValueError) as exc:
        raise PrayerError('invalid_file', 'A settings or schedule file could not be read.') from exc


def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def settings(raw):
    if not isinstance(raw, dict):
        raise PrayerError('invalid_settings', 'Settings must be a JSON object.')
    cfg = {**DEFAULTS, **{k: v for k, v in raw.items() if k in DEFAULTS}}
    # Existing explicit locations remain manual when upgrading from 0.1.
    if 'locationMode' not in raw and (raw.get('city') or raw.get('latitude') is not None):
        cfg['locationMode'] = 'manual'
    for key in ('city', 'country', 'timezone', 'soundFile', 'scheduleFile'):
        if not isinstance(cfg[key], str) or len(cfg[key]) > 4096:
            raise PrayerError('invalid_settings', f'Invalid {key}.')
        cfg[key] = cfg[key].strip()
    for key, low, high in [('beforeMinutes', 0, 120), ('afterMinutes', 0, 120),
                           ('method', 0, 23), ('school', 0, 1)]:
        value = cfg[key]
        if type(value) is not int or not low <= value <= high:
            raise PrayerError('invalid_settings', f'{key} must be between {low} and {high}.')
    for key in ('notifications', 'motion', 'countdown', 'clickOpensPanel', 'showQibla'):
        if not isinstance(cfg[key], bool):
            raise PrayerError('invalid_settings', f'{key} must be true or false.')
    for key, choices in [('provider', ('aladhan', 'file')), ('locationMode', ('auto', 'manual')), ('language', ('en', 'tr', 'ar')),
                         ('displayMode', ('earth', 'classic')), ('guidanceProfile', ('diyanet', 'off')),
                         ('countdownWindow', ('before', 'after', 'both')),
                         ('sound', ('off', 'chime', 'file'))]:
        if cfg[key] not in choices:
            raise PrayerError('invalid_settings', f'Invalid {key}.')
    if type(cfg['volume']) not in (int, float) or not 0 <= cfg['volume'] <= 1:
        raise PrayerError('invalid_settings', 'Volume must be between 0 and 1.')
    for key, limit in [('latitude', 90), ('longitude', 180)]:
        value = cfg[key]
        if value is not None and (type(value) not in (int, float) or not math.isfinite(value)
                                  or not -limit <= value <= limit):
            raise PrayerError('invalid_settings', f'Invalid {key}.')
    if (cfg['latitude'] is None) != (cfg['longitude'] is None):
        raise PrayerError('invalid_settings', 'Provide both latitude and longitude.')
    if cfg['timezone']:
        try:
            ZoneInfo(cfg['timezone'])
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise PrayerError('invalid_settings', 'Choose a valid IANA timezone.') from exc
    return cfg


def identity(cfg):
    keys = ('provider', 'city', 'country', 'latitude', 'longitude', 'timezone', 'method', 'school', 'scheduleFile')
    return hashlib.sha256(json.dumps({k: cfg[k] for k in keys}, sort_keys=True).encode()).hexdigest()[:20]


def api_json(url):
    try:
        request = Request(url, headers={'User-Agent': 'Omarchy-Salah/0.2', 'Accept': 'application/json'})
        with urlopen(request, timeout=10) as response:
            data = json.loads(response.read(2_000_000))
        if not isinstance(data, dict) or data.get('code') != 200:
            raise PrayerError('provider_error', 'The prayer-time provider rejected this request. Check the location and method.')
        return data['data']
    except HTTPError as exc:
        delay = retry_after_seconds(exc.headers.get('Retry-After') if exc.headers else None)
        geocoding_unavailable = False
        try:
            body = json.loads(exc.read(8192))
            detail = body.get('data') if isinstance(body, dict) else None
            geocoding_unavailable = isinstance(detail, str) and 'geocoding is temporarily unavailable' in detail.lower()
        except (ValueError, OSError, TypeError):
            pass
        finally:
            exc.close()
        if 500 <= exc.code <= 599:
            if geocoding_unavailable:
                error = PrayerError('geocoding_unavailable', f"AlAdhan's city lookup is temporarily unavailable (HTTP {exc.code}). Salah will retry automatically.", delay)
            else:
                error = PrayerError('provider_unavailable', f'AlAdhan is temporarily unavailable (HTTP {exc.code}). Salah will retry automatically.', delay)
        elif exc.code == 429:
            error = PrayerError('rate_limited', 'AlAdhan is limiting requests (HTTP 429). Salah will wait before retrying.', delay)
        elif exc.code == 400:
            error = PrayerError('provider_request', 'AlAdhan could not process the request (HTTP 400). Check the location and calculation settings.', delay)
        elif exc.code in (401, 403):
            error = PrayerError('provider_access', f'AlAdhan refused access (HTTP {exc.code}). Retry later or choose another timetable source.', delay)
        else:
            error = PrayerError('provider_error', f'AlAdhan returned HTTP {exc.code}. Salah will retry automatically.', delay)
        raise error from exc
    except (URLError, TimeoutError, OSError) as exc:
        raise PrayerError('network', 'Cannot reach the prayer-time provider. Check your connection; Salah will retry.') from exc
    except (ValueError, KeyError) as exc:
        raise PrayerError('invalid_schedule', 'The provider returned an unreadable schedule.') from exc


def normalize_location(raw):
    try:
        if not isinstance(raw, dict):
            raise ValueError('Invalid location')
        location = {key: raw[key] for key in ('city', 'country', 'latitude', 'longitude')}
        if not all(isinstance(location[k], str) and 0 < len(location[k].strip()) <= 256 for k in ('city', 'country')):
            raise ValueError('Missing city or country')
        for key, limit in [('latitude', 90), ('longitude', 180)]:
            value = location[key]
            if type(value) not in (int, float) or not math.isfinite(value) or not -limit <= value <= limit:
                raise ValueError('Invalid coordinates')
        return location
    except (KeyError, ValueError, TypeError) as exc:
        raise PrayerError('location', 'Automatic location is unavailable. Retry or choose a location manually in Settings.') from exc


def detect_location():
    # No saved address, name, or explicit IP is submitted. wttr.in estimates
    # the caller's city from the connection IP, as Omarchy weather does.
    try:
        request = Request('https://wttr.in/?format=j1', headers={'User-Agent': 'Omarchy-Salah/0.2', 'Accept': 'application/json'})
        with urlopen(request, timeout=10) as response:
            raw = json.loads(response.read(2_000_000))
        area = raw['nearest_area'][0]
        return normalize_location({'city': area['areaName'][0]['value'], 'country': area['country'][0]['value'],
                                   'latitude': float(area['latitude']), 'longitude': float(area['longitude'])})
    except (HTTPError, URLError, TimeoutError, OSError, ValueError, KeyError, IndexError, TypeError) as exc:
        raise PrayerError('location', 'Automatic location could not be detected. Check your connection or choose a city manually in Settings.') from exc


def resolve_location(cfg, state_dir, now, offline=False, force=False, locator=detect_location):
    if cfg['locationMode'] == 'manual':
        return cfg, ''
    cache_path = Path(state_dir)/'auto-location.json'
    cached = None
    detected_at = 0
    try:
        raw = read_json(cache_path, {})
        cached = normalize_location(raw.get('location'))
        detected_at = float(raw.get('detectedAt', 0))
        if not math.isfinite(detected_at):
            raise ValueError('Invalid timestamp')
    except (PrayerError, ValueError, TypeError, AttributeError):
        cached = None
    age = now.timestamp() - detected_at
    needs_lookup = not cached or force or not 0 <= age < 6*3600
    warning = ''
    if needs_lookup and not offline:
        try:
            cached = normalize_location(locator())
            atomic_json(cache_path, {'location': cached, 'detectedAt': now.timestamp()})
        except PrayerError:
            if not cached:
                raise
            warning = 'Automatic location could not be updated. Using the last detected city; check it if you have travelled.'
    elif offline and needs_lookup:
        warning = 'Offline: using the last detected location.'
    if not cached:
        raise PrayerError('location', 'No automatic location is cached yet. Connect to detect it, or choose a city manually.')
    # Automatic coordinates are transient; the user's saved manual choice is
    # retained so switching back to manual mode restores it.
    return {**cfg, **cached, 'timezone': ''}, warning


def normalize_day(day_date, timings, zone_name, hijri=''):
    try:
        zone = ZoneInfo(zone_name)
        start = datetime.combine(day_date, time(), zone)
        end = datetime.combine(day_date + timedelta(days=1), time(), zone)
        events = []
        last_at = None
        for name in ORDER:
            value = timings.get(name, '')
            match = re.fullmatch(r'(\d{2}):(\d{2})(?:\s+\([^\n]*\))?', str(value))
            if not match:
                raise ValueError(f'Missing or invalid {name}')
            hour, minute = map(int, match.groups())
            point = datetime.combine(day_date, time(hour, minute), zone)
            # At high latitudes Isha can be expressed after midnight.
            if last_at is not None and point.timestamp() <= last_at:
                if name == 'Isha':
                    point += timedelta(days=1)
                else:
                    raise ValueError('Prayer order is invalid')
            last_at = point.timestamp()
            events.append({'name': name, 'time': f'{hour:02}:{minute:02}', 'at': int(last_at * 1000)})
        return {'date': day_date.isoformat(), 'start': int(start.timestamp()*1000),
                'end': int(end.timestamp()*1000), 'hijri': str(hijri), 'events': events}
    except (ValueError, TypeError, AttributeError, ZoneInfoNotFoundError) as exc:
        raise PrayerError('invalid_schedule', 'The schedule has missing times, an invalid order, or an unknown timezone.') from exc


def fetch_day(cfg, target):
    params = {'method': cfg['method'], 'school': cfg['school']}
    if cfg['latitude'] is not None:
        endpoint = 'timings'
        params.update(latitude=cfg['latitude'], longitude=cfg['longitude'])
    else:
        endpoint = 'timingsByCity'
        params.update(city=cfg['city'], country=cfg['country'])
    if cfg['timezone']:
        params['timezonestring'] = cfg['timezone']
    data = api_json(f'https://api.aladhan.com/v1/{endpoint}/{target:%d-%m-%Y}?' + urlencode(params))
    try:
        actual = datetime.strptime(data['date']['gregorian']['date'], '%d-%m-%Y').date()
        if actual != target:
            raise ValueError('Wrong date')
        if cfg['latitude'] is not None:
            # A successful HTTP response is insufficient: reject a timetable
            # calculated for coordinates other than the ones requested.
            for key, limit in [('latitude', 90), ('longitude', 180)]:
                value = data['meta'].get(key)
                if (type(value) not in (int, float) or not math.isfinite(value)
                        or not -limit <= value <= limit
                        or not math.isclose(value, cfg[key], rel_tol=0, abs_tol=0.0001)):
                    raise PrayerError('location_mismatch', 'AlAdhan returned a timetable for different coordinates. No new times were saved; Salah will retry.')
        zone_name = data['meta']['timezone']
        hijri = data['date'].get('hijri', {})
        label = ' '.join(str(v) for v in [hijri.get('day', ''), hijri.get('month', {}).get('en', ''), hijri.get('year', '')])
        day = normalize_day(actual, data['timings'], zone_name, label.strip())
        coordinates = {k: data['meta'].get(k) for k in ('latitude', 'longitude')}
        if all(type(coordinates[k]) in (int, float) and math.isfinite(coordinates[k])
               and abs(coordinates[k]) <= limit for k, limit in [('latitude', 90), ('longitude', 180)]):
            day['coordinates'] = coordinates
        return zone_name, day
    except (KeyError, TypeError, ValueError) as exc:
        raise PrayerError('invalid_schedule', 'The provider returned a schedule for an unexpected date.') from exc


def file_schedule(cfg, now):
    if not cfg['scheduleFile']:
        raise PrayerError('setup', 'Choose a local timetable JSON file in Settings.')
    raw = read_json(Path(cfg['scheduleFile']).expanduser(), None)
    if not isinstance(raw, dict) or not isinstance(raw.get('days'), list):
        raise PrayerError('invalid_schedule', 'The timetable must contain a timezone and a days array.')
    try:
        zone_name = raw['timezone']
        today = now.astimezone(ZoneInfo(zone_name)).date()
        days = [normalize_day(date.fromisoformat(d['date']), d['timings'], zone_name, d.get('hijri', '')) for d in raw['days']]
        days = sorted((d for d in days if abs((date.fromisoformat(d['date'])-today).days) <= 1), key=lambda d: d['date'])
        if not any(d['date'] == today.isoformat() for d in days):
            raise PrayerError('expired', 'The local timetable has no times for today. Import an updated timetable.')
        result = {'identity': identity(cfg), 'location': str(raw.get('location', 'Local timetable')),
                  'timezone': zone_name, 'days': days, 'source': 'file', 'cached': True}
        if isinstance(raw.get('coordinates'), dict):
            validated = settings({'locationMode':'manual', **raw['coordinates']})
            if validated['latitude'] is not None:
                result['coordinates'] = {k: validated[k] for k in ('latitude', 'longitude')}
        return result
    except (KeyError, ValueError, TypeError, ZoneInfoNotFoundError) as exc:
        raise PrayerError('invalid_schedule', 'The local timetable has an invalid date or timezone.') from exc


def load_schedule(cfg, state_dir, now=None, offline=False, force=False, fetcher=fetch_day, locator=detect_location):
    now = now or datetime.now(timezone.utc)
    if cfg['provider'] == 'file':
        return file_schedule(cfg, now)
    resolved, location_warning = resolve_location(cfg, state_dir, now, offline, force, locator)
    result = load_resolved_schedule(resolved, state_dir, now, offline, force, fetcher)
    result['locationMode'] = cfg['locationMode']
    if location_warning:
        result['warning'] = ' '.join(filter(None, [location_warning, result.get('warning')]))
    return result


def load_resolved_schedule(cfg, state_dir, now, offline, force, fetcher):
    if cfg['latitude'] is None and (not cfg['city'] or not cfg['country']):
        raise PrayerError('setup', 'Choose your city and country in Settings to get started.')
    key = identity(cfg)
    cache_path = Path(state_dir)/('schedule-' + key + '.json')
    try:
        cached = read_json(cache_path, {})
    except PrayerError:
        cached = {}
    if not isinstance(cached, dict) or cached.get('identity') != key:
        cached = {}
    zone_name = cfg['timezone'] or cached.get('timezone') or 'UTC'
    today = now.astimezone(ZoneInfo(zone_name)).date()
    # Discover the selected location's timezone from the first response.
    days = {d['date']: d for d in cached.get('days', []) if isinstance(d, dict) and 'date' in d}
    fetched = False
    errors = []
    if not cfg['timezone'] and not cached and not offline:
        zone_name, seed = fetcher(cfg, today)
        days[seed['date']] = seed
        fetched = True
        today = now.astimezone(ZoneInfo(zone_name)).date()
    required = [today + timedelta(days=n) for n in (-1, 0, 1)]
    missing = [d for d in required if force or d.isoformat() not in days]
    if missing and not offline:
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            futures = {pool.submit(fetcher, cfg, d): d for d in missing}
            for future in concurrent.futures.as_completed(futures):
                try:
                    actual_zone, day = future.result()
                    if actual_zone != zone_name:
                        raise PrayerError('invalid_schedule', 'The provider returned inconsistent timezones.')
                    days[day['date']] = day
                    fetched = True
                except PrayerError as exc:
                    errors.append((futures[future], exc))
    selected = [days[d.isoformat()] for d in required if d.isoformat() in days]
    if today.isoformat() not in days:
        if errors:
            # Preserve the status and Retry-After for today's failed request.
            raise next((exc for target, exc in errors if target == today), errors[0][1])
        raise PrayerError('expired', 'No cached schedule for today. Connect to fetch new times.')
    result = {'identity': key, 'location': ', '.join(filter(None, [cfg['city'], cfg['country']])) or 'Selected coordinates',
              'timezone': zone_name, 'days': selected, 'source': 'aladhan', 'cached': not fetched}
    coordinates = ({k: cfg[k] for k in ('latitude', 'longitude')} if cfg['latitude'] is not None
                   else days[today.isoformat()].get('coordinates'))
    if coordinates:
        result['coordinates'] = coordinates
    if errors:
        result['warning'] = str(errors[0][1]) + ' Available saved dates remain usable.'
        delays = [exc.retry_after for _, exc in errors if exc.retry_after is not None]
        if delays:
            result['retryAfterSeconds'] = max(delays)
    elif any(d.isoformat() not in days for d in required):
        result['warning'] = 'Some adjacent-day times are unavailable. Cached dates remain usable; Salah will retry.'
    if fetched:
        # A failed request's retry delay is transient, not part of the timetable.
        atomic_json(cache_path, {k: v for k, v in result.items() if k not in ('warning', 'retryAfterSeconds')})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config'))/'salah'/'config.json')
    parser.add_argument('--state', type=Path, default=Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'salah')
    parser.add_argument('action', choices=('config', 'configure', 'schedule'))
    parser.add_argument('payload', nargs='?')
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()
    try:
        if args.action == 'configure':
            cfg = settings(json.loads(args.payload or '{}'))
            atomic_json(args.config, cfg)
            output = {'ok': True, 'config': cfg}
        else:
            cfg = settings(read_json(args.config, {}))
            if args.action == 'config':
                args.state.mkdir(parents=True, exist_ok=True)
            output = {'ok': True, 'config': cfg} if args.action == 'config' else load_schedule(cfg, args.state, offline=args.offline, force=args.force)
        print(json.dumps(output, ensure_ascii=False))
        return 0
    except PrayerError as exc:
        print(json.dumps(exc.as_dict()))
        return 1
    except (ValueError, OSError) as exc:
        print(json.dumps({'error': 'Could not read or save Salah settings.', 'code': 'storage'}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
