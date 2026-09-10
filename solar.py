#!/usr/bin/env python3
"""Local solar ephemeris. This module never makes network requests."""
import argparse
from datetime import date,datetime,time,timedelta,timezone
import hashlib
import json
import math
import os
from pathlib import Path
from zoneinfo import ZoneInfo,ZoneInfoNotFoundError
from vendor import astronomy as A
from prayer import PrayerError,atomic_json,read_json

ENGINE='astronomy-engine-865d3da7-v1'
J2000=946728000

def location(raw):
    if not isinstance(raw,dict): raise PrayerError('solar_location','Coordinates are needed for the Earth view.')
    out={}
    for key,limit in [('latitude',90),('longitude',180)]:
        v=raw.get(key)
        if type(v) not in (int,float) or not math.isfinite(v) or not -limit<=v<=limit:
            raise PrayerError('solar_location','Valid coordinates are needed for the Earth view.')
        out[key]=v
    zone=raw.get('timezone') or ''
    if not zone:
        path=str(Path('/etc/localtime').resolve())
        zone=path.split('/zoneinfo/',1)[-1] if '/zoneinfo/' in path else 'UTC'
    try: ZoneInfo(zone)
    except (ZoneInfoNotFoundError,ValueError,TypeError):
        raise PrayerError('solar_timezone','A valid timezone is needed for the Earth view.')
    return {**out,'timezone':zone}

def astro(ms): return A.Time((ms/1000-J2000)/86400)
def millis(t): return round((t.ut*86400+J2000)*1000) if t else None

def position(loc,ms):
    t=astro(ms)
    eq=A.EquatorFromVector(A.RotateVector(A.Rotation_EQJ_EQD(t),A.GeoVector(A.Body.Sun,t,True)))
    lng=math.radians(eq.ra*15-A.SiderealTime(t)*15); dec=math.radians(eq.dec)
    vector=[math.cos(dec)*math.cos(lng),math.cos(dec)*math.sin(lng),math.sin(dec)]
    observer=A.Observer(loc['latitude'],loc['longitude'],0)
    top=A.Equator(A.Body.Sun,t,observer,True,True)
    h=A.Horizon(t,observer,top.ra,top.dec,A.Refraction.Normal)
    offset=datetime.fromtimestamp(ms/1000,ZoneInfo(loc['timezone'])).utcoffset().total_seconds()/60
    return [round(ms),*[round(v,9) for v in vector],round(h.altitude,5),round(h.azimuth,5),offset]

def day_bounds(target,zone):
    z=ZoneInfo(zone)
    return [round(datetime.combine(d,time(),z).timestamp()*1000) for d in [target,target+timedelta(days=1)]]

def calculate_day(loc,target):
    loc=location(loc); start,end=day_bounds(target,loc['timezone'])
    obs=A.Observer(loc['latitude'],loc['longitude'],0); t=astro(start); limit=(end-start)/86400000
    def within(value):
        ms=millis(value)
        return ms if ms is not None and start<=ms<end else None
    events={}
    for direction,key in [(A.Direction.Rise,'sunrise'),(A.Direction.Set,'sunset')]:
        events[key]=within(A.SearchRiseSet(A.Body.Sun,obs,direction,t,limit))
        for angle,name in [(-6,'civil'),(-12,'nautical'),(-18,'astronomical')]:
            events[name+('Dawn' if direction==A.Direction.Rise else 'Dusk')]=within(A.SearchAltitude(A.Body.Sun,obs,direction,t,limit,angle))
    events['solarNoon']=within(A.SearchHourAngle(A.Body.Sun,obs,0,t).time)
    samples=[position(loc,ms) for ms in range(start,end,60000)]+[position(loc,end)]
    regime='normal'
    if events['sunrise'] is None or events['sunset'] is None:
        alts=[s[4] for s in samples]
        regime='polarDay' if min(alts)>0 else 'polarNight' if max(alts)<0 else 'partialDay'
    return {'date':target.isoformat(),'start':start,'end':end,'events':events,'samples':samples,'regime':regime}

def load(loc,state_dir,now=None):
    loc=location(loc); now=now or datetime.now(timezone.utc)
    today=now.astimezone(ZoneInfo(loc['timezone'])).date()
    key=hashlib.sha256(json.dumps([ENGINE,loc],sort_keys=True).encode()).hexdigest()[:20]
    days=[]; root=Path(state_dir)
    for delta in (-1,0,1):
        target=today+timedelta(days=delta); path=root/f'solar-{key}-{target}.json'
        try: cached=read_json(path,{})
        except PrayerError: cached={}
        bounds=day_bounds(target,loc['timezone'])
        valid=(isinstance(cached,dict) and cached.get('engine')==ENGINE and cached.get('location')==loc
               and cached.get('day',{}).get('date')==target.isoformat()
               and [cached.get('day',{}).get(k) for k in ('start','end')]==bounds
               and len(cached.get('day',{}).get('samples',[]))==round((bounds[1]-bounds[0])/60000)+1)
        if not valid:
            cached={'engine':ENGINE,'location':loc,'day':calculate_day(loc,target)}
            atomic_json(path,cached)
        days.append(cached['day'])
    # Solar data is deterministic and can be rebuilt; retain only a fortnight.
    for path in root.glob('solar-*.json'):
        try:
            if (now.timestamp()-path.stat().st_mtime)>14*86400: path.unlink()
        except OSError: pass
    return {'engine':ENGINE,'identity':key,'location':loc,'timezone':loc['timezone'],'localDate':today.isoformat(),'days':days,
            'assumptions':'standard-atmosphere-level-horizon','sampleStep':60000}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--location',required=True)
    parser.add_argument('--state',type=Path,default=Path(os.environ.get('XDG_STATE_HOME',Path.home()/'.local/state'))/'salah')
    args=parser.parse_args()
    try:
        result=load(json.loads(args.location),args.state)
        print(json.dumps(result,separators=(',',':')))
    except (PrayerError,ValueError,OSError) as exc:
        print(json.dumps({'code':getattr(exc,'code','solar_error'),'error':str(exc)}));return 1
    return 0
if __name__=='__main__':raise SystemExit(main())
