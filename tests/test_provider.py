import importlib.util
from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from io import BytesIO
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location('prayer', Path(__file__).parents[1]/'prayer.py')
P = importlib.util.module_from_spec(spec)
spec.loader.exec_module(P)
TIMES = dict(Fajr='05:10', Sunrise='06:40', Dhuhr='12:50', Asr='16:20', Maghrib='19:00', Isha='20:30')
NOW = datetime(2026, 9, 9, 12, tzinfo=timezone.utc)


class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.cfg = P.settings({'city':'Fixture city', 'country':'Fixture country', 'timezone':'Europe/London'})
        self.calls = []

    def fetch(self, cfg, day):
        self.calls.append(day)
        return 'Europe/London', P.normalize_day(day, TIMES, 'Europe/London')

    def test_setup_does_not_make_a_request(self):
        with self.assertRaisesRegex(P.PrayerError, 'Choose your city'):
            P.load_schedule(P.settings({'locationMode':'manual'}), self.path, NOW, fetcher=self.fetch)
        self.assertEqual(self.calls, [])

    def test_new_install_defaults_to_auto_but_existing_locations_stay_manual(self):
        self.assertEqual(P.settings({})['locationMode'], 'auto')
        self.assertEqual(P.settings({'city':'Saved city'})['locationMode'], 'manual')
        self.assertEqual(P.settings({'latitude':0,'longitude':0})['locationMode'], 'manual')
        self.assertEqual(P.settings({'city':'Saved city','locationMode':'auto'})['locationMode'], 'auto')

    def test_earth_upgrade_preserves_saved_location_method_and_reminders(self):
        old={'latitude':12.5,'longitude':45.5,'timezone':'UTC','method':13,'school':0,
             'beforeMinutes':30,'afterMinutes':30,'sound':'off','notifications':False}
        cfg=P.settings(old)
        self.assertEqual({k:cfg[k] for k in old},old)
        self.assertEqual(cfg['locationMode'],'manual')
        self.assertEqual(cfg['displayMode'],'earth')
        self.assertEqual(cfg['guidanceProfile'],'diyanet')
        self.assertFalse(cfg['showQibla'])

    def test_qibla_visibility_persists_without_changing_timetable_identity(self):
        visible=P.settings({**self.cfg,'showQibla':True})
        self.assertEqual(P.identity(visible),P.identity(self.cfg))
        path=self.path/'config.json'
        P.atomic_json(path,visible)
        self.assertTrue(P.settings(P.read_json(path,{}))['showQibla'])
        for value in ('true',1,None):
            with self.assertRaises(P.PrayerError):P.settings({'showQibla':value})

    def test_countdown_window_defaults_and_validation(self):
        self.assertEqual(P.settings({})['countdownWindow'],'both')
        for value in ('before','after','both'):
            self.assertEqual(P.settings({'countdownWindow':value})['countdownWindow'],value)
        for value in ('always',True,None):
            with self.assertRaises(P.PrayerError):P.settings({'countdownWindow':value})

    def test_auto_location_is_cached_without_overwriting_manual_preferences(self):
        cfg=P.settings({'city':'Saved city','country':'Saved country','locationMode':'auto'})
        located={'city':'Detected city','country':'Detected country','latitude':1.5,'longitude':2.5}
        calls=[]
        def locator(): calls.append(1); return located
        resolved,warning=P.resolve_location(cfg,self.path,NOW,locator=locator)
        self.assertEqual(resolved['city'],'Detected city')
        self.assertEqual(cfg['city'],'Saved city')
        self.assertEqual(warning,'')
        P.resolve_location(cfg,self.path,NOW+timedelta(hours=1),locator=locator)
        self.assertEqual(len(calls),1)
        raw=json.loads((self.path/'auto-location.json').read_text())
        self.assertEqual(set(raw),{'location','detectedAt'})

    def test_auto_location_refreshes_after_six_hours_and_on_forced_refresh(self):
        cfg=P.settings({})
        calls=[]
        def locator():
            calls.append(1)
            return {'city':'Fixture','country':'Fixture','latitude':0,'longitude':0}
        P.resolve_location(cfg,self.path,NOW,locator=locator)
        P.resolve_location(cfg,self.path,NOW+timedelta(hours=6),locator=locator)
        P.resolve_location(cfg,self.path,NOW+timedelta(hours=6),force=True,locator=locator)
        self.assertEqual(len(calls),3)

    def test_auto_location_works_offline_and_warns_when_last_location_cannot_be_updated(self):
        cfg=P.settings({})
        located={'city':'Fixture','country':'Fixture','latitude':1,'longitude':2}
        P.resolve_location(cfg,self.path,NOW,locator=lambda:located)
        def broken(): raise P.PrayerError('location','Unavailable')
        resolved,warning=P.resolve_location(cfg,self.path,NOW+timedelta(days=1),locator=broken)
        self.assertEqual(resolved['city'],'Fixture')
        self.assertIn('last detected city',warning)
        resolved,warning=P.resolve_location(cfg,self.path,NOW+timedelta(days=1),offline=True,
                                            locator=lambda:self.fail('Unexpected network call'))
        self.assertEqual(resolved['latitude'],1)
        self.assertIn('Offline',warning)

    def test_first_auto_failure_has_actionable_error_and_manual_mode_never_detects(self):
        def broken(): raise P.PrayerError('location','Choose manually')
        with self.assertRaisesRegex(P.PrayerError,'Choose manually'):
            P.resolve_location(P.settings({}),self.path,NOW,locator=broken)
        with self.assertRaisesRegex(P.PrayerError,'No automatic location'):
            P.resolve_location(P.settings({}),self.path,NOW,offline=True,locator=broken)
        resolved,warning=P.resolve_location(self.cfg,self.path,NOW,locator=lambda:self.fail('Unexpected detection'))
        self.assertEqual(resolved,self.cfg)

    def test_detector_reads_wttr_city_coordinates_and_handles_bad_response(self):
        data={'nearest_area':[{'areaName':[{'value':'Fixture city'}],'country':[{'value':'Fixture country'}],
                               'latitude':'0','longitude':'0'}]}
        with patch.object(P,'urlopen',return_value=BytesIO(json.dumps(data).encode())) as request:
            self.assertEqual(P.detect_location()['latitude'],0)
            self.assertEqual(request.call_args.args[0].full_url,'https://wttr.in/?format=j1')
        with patch.object(P,'urlopen',return_value=BytesIO(b'{"nearest_area":[]}')):
            with self.assertRaises(P.PrayerError): P.detect_location()

    def test_auto_mode_fetches_detected_coordinates_and_switches_schedule_cache_on_travel(self):
        cfg=P.settings({})
        one={'city':'First fixture','country':'Fixture','latitude':1,'longitude':2}
        two={**one,'city':'Second fixture','latitude':3}
        seen=[]
        def fetch(cfg,day):
            seen.append(cfg['latitude'])
            return 'UTC',P.normalize_day(day,TIMES,'UTC')
        first=P.load_schedule(cfg,self.path,NOW,fetcher=fetch,locator=lambda:one)
        second=P.load_schedule(cfg,self.path,NOW+timedelta(hours=6),fetcher=fetch,locator=lambda:two)
        self.assertNotEqual(first['identity'],second['identity'])
        self.assertEqual(second['locationMode'],'auto')
        self.assertIn(1,seen)
        self.assertIn(3,seen)

    def test_three_distinct_days_are_cached_and_work_offline(self):
        result = P.load_schedule(self.cfg, self.path, NOW, fetcher=self.fetch)
        self.assertEqual(len(result['days']), 3)
        self.assertEqual(len(self.calls), 3)
        result = P.load_schedule(self.cfg, self.path, NOW, offline=True, fetcher=self.fetch)
        self.assertTrue(result['cached'])
        self.assertEqual(len(self.calls), 3)

    def test_changed_location_or_method_cannot_reuse_old_cache(self):
        P.load_schedule(self.cfg, self.path, NOW, fetcher=self.fetch)
        for key,value in [('city','Another fixture'),('method',13),('school',1)]:
            with self.subTest(key=key), self.assertRaises(P.PrayerError):
                P.load_schedule({**self.cfg,key:value},self.path,NOW,offline=True)

    def test_next_day_offline_uses_only_dates_actually_cached(self):
        P.load_schedule(self.cfg,self.path,NOW,fetcher=self.fetch)
        result = P.load_schedule(self.cfg,self.path,NOW+timedelta(days=1),offline=True)
        self.assertIn('warning',result)
        self.assertEqual(result['days'][-1]['date'],'2026-09-10')
        with self.assertRaises(P.PrayerError):
            P.load_schedule(self.cfg,self.path,NOW+timedelta(days=2),offline=True)

    def test_network_failure_preserves_valid_cached_times(self):
        result = P.load_schedule(self.cfg,self.path,NOW,fetcher=self.fetch)
        def broken(*args): raise P.PrayerError('network','Offline')
        fallback = P.load_schedule(self.cfg,self.path,NOW,force=True,fetcher=broken)
        self.assertEqual(result['days'],fallback['days'])
        self.assertIn('warning',fallback)

    def test_http_errors_distinguish_outages_from_invalid_requests(self):
        for status,code in [(500,'provider_unavailable'),(502,'provider_unavailable'),
                            (503,'provider_unavailable'),(504,'provider_unavailable'),
                            (429,'rate_limited'),(400,'provider_request'),(403,'provider_access')]:
            with self.subTest(status=status):
                error=HTTPError('https://example.invalid',status,'Fixture',{'Retry-After':'600'},None)
                with patch.object(P,'urlopen',side_effect=error) as request:
                    with self.assertRaises(P.PrayerError) as raised: P.api_json('https://example.invalid')
                self.assertEqual(raised.exception.code,code)
                self.assertEqual(raised.exception.as_dict()['retryAfterSeconds'],600)
                self.assertEqual(request.call_count,1, 'Retries belong to the desktop timer')
                if status >= 500:
                    self.assertNotIn('location',str(raised.exception).lower())
                    self.assertIn(str(status),str(raised.exception))

    def test_retry_after_accepts_delays_and_http_dates(self):
        self.assertEqual(P.retry_after_seconds('120',NOW),120)
        self.assertEqual(P.retry_after_seconds('Wed, 09 Sep 2026 12:10:00 GMT',NOW),600)
        self.assertEqual(P.retry_after_seconds('Wed, 09 Sep 2026 11:00:00 GMT',NOW),0)
        for raw in [None,'','invalid','-5','1.5','9'*100]:
            with self.subTest(raw=raw): self.assertIsNone(P.retry_after_seconds(raw,NOW))

    def test_geocoding_outage_reports_the_specific_failed_service(self):
        body=BytesIO(json.dumps({'code':503,'status':'SERVER_ERROR',
                                'data':'Geocoding is temporarily unavailable. Please try again later.'}).encode())
        error=HTTPError('https://example.invalid',503,'Fixture',{'Retry-After':'120'},body)
        with patch.object(P,'urlopen',side_effect=error):
            with self.assertRaises(P.PrayerError) as raised: P.api_json('https://example.invalid')
        self.assertEqual(raised.exception.code,'geocoding_unavailable')
        self.assertIn('city lookup is temporarily unavailable',str(raised.exception))
        self.assertEqual(raised.exception.retry_after,120)
        self.assertTrue(body.closed)

    def test_today_failure_preserves_http_status_and_retry_delay(self):
        def broken(*args): raise P.PrayerError('provider_unavailable','AlAdhan unavailable',600)
        with self.assertRaises(P.PrayerError) as raised:
            P.load_schedule(self.cfg,self.path,NOW,fetcher=broken)
        self.assertEqual(raised.exception.code,'provider_unavailable')
        self.assertEqual(raised.exception.retry_after,600)
        self.assertEqual(list(self.path.glob('schedule-*.json')),[])

    def test_first_timezone_lookup_preserves_outage_error(self):
        def broken(*args): raise P.PrayerError('provider_unavailable','AlAdhan unavailable',120)
        with self.assertRaises(P.PrayerError) as raised:
            P.load_schedule({**self.cfg,'timezone':''},self.path,NOW,fetcher=broken)
        self.assertEqual(raised.exception.as_dict()['retryAfterSeconds'],120)

    def test_coordinate_requests_reject_timetables_for_another_location(self):
        cfg=P.settings({'locationMode':'manual','latitude':12.3,'longitude':45.6})
        target=NOW.date()
        data={'date':{'gregorian':{'date':target.strftime('%d-%m-%Y')}},
              'meta':{'timezone':'UTC','latitude':12.3,'longitude':45.6},'timings':TIMES}
        with patch.object(P,'api_json',return_value=data) as request:
            zone,day=P.fetch_day(cfg,target)
            self.assertEqual(zone,'UTC')
            self.assertIn('/timings/',request.call_args.args[0])
            self.assertIn('latitude=12.3',request.call_args.args[0])
        for wrong in [{'latitude':8.8888888,'longitude':7.7777777}, {'latitude':None},
                      {'longitude':float('nan')}, {'latitude':True}, {'longitude':'45.6'}]:
            with self.subTest(wrong=wrong):
                response={**data,'meta':{**data['meta'],**wrong}}
                with patch.object(P,'api_json',return_value=response):
                    with self.assertRaises(P.PrayerError) as raised:
                        P.load_schedule(cfg,self.path,NOW)
                self.assertEqual(raised.exception.code,'location_mismatch')
                self.assertEqual(list(self.path.glob('schedule-*.json')),[])

    def test_coordinate_check_allows_normal_provider_rounding(self):
        cfg=P.settings({'locationMode':'manual','latitude':12.3456789,'longitude':45.6789123})
        data={'date':{'gregorian':{'date':NOW.strftime('%d-%m-%Y')}},
              'meta':{'timezone':'UTC','latitude':12.345679,'longitude':45.678912},'timings':TIMES}
        with patch.object(P,'api_json',return_value=data):
            self.assertEqual(P.fetch_day(cfg,NOW.date())[0],'UTC')

    def test_outage_keeps_cached_times_and_success_clears_retry_delay(self):
        original=P.load_schedule(self.cfg,self.path,NOW,fetcher=self.fetch)
        def broken(*args): raise P.PrayerError('provider_unavailable','AlAdhan unavailable (HTTP 503).',600)
        fallback=P.load_schedule(self.cfg,self.path,NOW,force=True,fetcher=broken)
        self.assertEqual(fallback['days'],original['days'])
        self.assertEqual(fallback['retryAfterSeconds'],600)
        self.assertIn('503',fallback['warning'])
        recovered=P.load_schedule(self.cfg,self.path,NOW,force=True,fetcher=self.fetch)
        self.assertNotIn('retryAfterSeconds',recovered)
        self.assertNotIn('warning',recovered)

    def test_partial_fetch_does_not_store_transient_retry_information(self):
        def partial(cfg,day):
            if day > NOW.date(): raise P.PrayerError('rate_limited','Fixture rate limit',900)
            return self.fetch(cfg,day)
        result=P.load_schedule(self.cfg,self.path,NOW,fetcher=partial)
        self.assertEqual(result['retryAfterSeconds'],900)
        saved=json.loads(next(self.path.glob('schedule-*.json')).read_text())
        self.assertNotIn('retryAfterSeconds',saved)
        self.assertNotIn('warning',saved)

    def test_dst_day_lengths_and_timezone_offsets(self):
        spring=P.normalize_day(date(2026,3,29),TIMES,'Europe/London')
        autumn=P.normalize_day(date(2026,10,25),TIMES,'Europe/London')
        self.assertEqual(spring['end']-spring['start'],23*3600000)
        self.assertEqual(autumn['end']-autumn['start'],25*3600000)
        summer=P.normalize_day(date(2026,9,9),TIMES,'Europe/London')
        self.assertEqual(datetime.fromtimestamp(summer['events'][0]['at']/1000,timezone.utc).hour,4)

    def test_isha_can_cross_midnight(self):
        day=P.normalize_day(date(2026,9,9),{**TIMES,'Isha':'00:15'},'UTC')
        self.assertGreater(day['events'][-1]['at'],day['end'])

    def test_invalid_times_and_missing_prayers_are_rejected(self):
        for invalid in [{**TIMES,'Fajr':'99:00'},{**TIMES,'Fajr':'-----'}, {**TIMES,'Asr':None}, {**TIMES,'Asr':'01:00'}]:
            with self.subTest(invalid=invalid), self.assertRaises(P.PrayerError):
                P.normalize_day(date(2026,9,9),invalid,'UTC')

    def test_corrupt_cache_is_rebuilt(self):
        (self.path/('schedule-'+P.identity(self.cfg)+'.json')).write_text('{bad')
        self.assertEqual(len(P.load_schedule(self.cfg,self.path,NOW,fetcher=self.fetch)['days']),3)

    def test_settings_reject_invalid_types_and_coordinates(self):
        for invalid in [{'beforeMinutes':-1},{'afterMinutes':True},{'volume':float('nan')},{'latitude':100},
                        {'latitude':0},{'notifications':'yes'},{'timezone':'Not/AZone'}]:
            with self.subTest(invalid=invalid), self.assertRaises(P.PrayerError): P.settings(invalid)
        self.assertEqual(P.settings({'latitude':0,'longitude':0})['latitude'],0)

    def test_imported_timetable_never_needs_network(self):
        path=self.path/'local.json'
        path.write_text(json.dumps({'location':'Fixture mosque','timezone':'UTC','days':[
            {'date':'2026-09-09','timings':TIMES}]}))
        cfg=P.settings({'provider':'file','scheduleFile':str(path)})
        result=P.load_schedule(cfg,self.path,NOW,fetcher=lambda *args:self.fail('Unexpected network access'))
        self.assertEqual(result['location'],'Fixture mosque')
        self.assertEqual(result['source'],'file')
        with self.assertRaises(P.PrayerError): P.load_schedule(cfg,self.path,NOW+timedelta(days=1))

    def test_import_coordinates_are_optional_and_independent_of_saved_api_location(self):
        path=self.path/'earth.json'
        raw={'timezone':'UTC','days':[{'date':'2026-09-09','timings':TIMES}]}
        cfg=P.settings({'provider':'file','scheduleFile':str(path),'latitude':10,'longitude':20})
        path.write_text(json.dumps(raw))
        self.assertNotIn('coordinates',P.file_schedule(cfg,NOW))
        raw['coordinates']={'latitude':0,'longitude':0}
        path.write_text(json.dumps(raw))
        self.assertEqual(P.file_schedule(cfg,NOW)['coordinates'],raw['coordinates'])
        raw['coordinates']['latitude']=91
        path.write_text(json.dumps(raw))
        with self.assertRaises(P.PrayerError):P.file_schedule(cfg,NOW)

    def test_city_response_coordinates_survive_offline_cache(self):
        coordinates={'latitude':51.5,'longitude':0}
        def response(url):
            return {'date':{'gregorian':{'date':url.split('/')[-1].split('?')[0]}},
                    'meta':{'timezone':'Europe/London',**coordinates},'timings':TIMES}
        with patch.object(P,'api_json',side_effect=response):
            P.load_schedule(self.cfg,self.path,NOW,fetcher=P.fetch_day)
        cached=P.load_schedule(self.cfg,self.path,NOW,offline=True)
        self.assertEqual(cached['coordinates'],coordinates)

    def test_first_lookup_uses_remote_timezone_to_pick_the_current_day(self):
        cfg=P.settings({'city':'Test','country':'Test'})
        now=datetime(2026,9,9,23,30,tzinfo=timezone.utc)
        def fetch(cfg,day): return 'Asia/Tokyo',P.normalize_day(day,TIMES,'Asia/Tokyo')
        result=P.load_schedule(cfg,self.path,now,fetcher=fetch)
        self.assertEqual([d['date'] for d in result['days']],['2026-09-09','2026-09-10','2026-09-11'])


if __name__ == '__main__': unittest.main()
