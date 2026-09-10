from datetime import date,datetime,timedelta,timezone
import json,math
from pathlib import Path
import tempfile,unittest
from unittest.mock import patch
import solar

class SolarTests(unittest.TestCase):
    def test_independent_usno_reference_events_within_two_minutes(self):
        mapping={'Begin Civil Twilight':'civilDawn','Rise':'sunrise','Upper Transit':'solarNoon','Set':'sunset','End Civil Twilight':'civilDusk'}
        for path in (Path(__file__).parent/'fixtures').glob('*-*.json'):
            raw=json.loads(path.read_text())['data'];info=raw['properties']['data'];lon,lat=raw['geometry']['coordinates']
            target=date(info['year'],info['month'],info['day'])
            zone='Australia/Sydney' if path.stem=='sydney-solstice' else 'Europe/London'
            d=solar.calculate_day({'latitude':lat,'longitude':lon,'timezone':zone},target)
            for event in info['sundata']:
                with self.subTest(site=path.stem,event=event['phen']):
                    h,m=map(int,event['time'].split(':'))
                    expected=datetime(target.year,target.month,target.day,h,m,tzinfo=timezone(timedelta(hours=info['tz']))).timestamp()*1000
                    self.assertLess(abs(d['events'][mapping[event['phen']]]-expected),120000)

    def test_dst_days_have_correct_sample_counts_and_offsets(self):
        loc={'latitude':51.5,'longitude':0,'timezone':'Europe/London'}
        for target,hours in [(date(2026,3,29),23),(date(2026,10,25),25)]:
            with self.subTest(target=target):
                d=solar.calculate_day(loc,target)
                self.assertEqual(d['end']-d['start'],hours*3600000)
                self.assertEqual(len(d['samples']),hours*60+1)
                self.assertNotEqual(d['samples'][0][6],d['samples'][-1][6])

    def test_polar_day_and_night_do_not_invent_rise_or_set(self):
        loc={'latitude':78.22,'longitude':15.65,'timezone':'Arctic/Longyearbyen'}
        for target,regime in [(date(2026,6,21),'polarDay'),(date(2026,12,21),'polarNight')]:
            d=solar.calculate_day(loc,target)
            self.assertEqual(d['regime'],regime)
            self.assertIsNone(d['events']['sunrise']);self.assertIsNone(d['events']['sunset'])

    def test_vector_is_unit_length_and_local_altitude_matches_direction(self):
        for lat,lon in [(41.0082,28.9784),(0,179.9),(-45,-179.9),(90,0)]:
            loc={'latitude':lat,'longitude':lon,'timezone':'UTC'}
            s=solar.position(loc,datetime(2026,9,9,12,tzinfo=timezone.utc).timestamp()*1000)
            self.assertAlmostEqual(sum(v*v for v in s[1:4]),1,places=7)
            p,l=map(math.radians,[lat,lon]);up=[math.cos(p)*math.cos(l),math.cos(p)*math.sin(l),math.sin(p)]
            geometric=math.degrees(math.asin(sum(a*b for a,b in zip(s[1:4],up))))
            self.assertLess(abs(s[4]-geometric),1) # apparent refraction differs near the horizon

    def test_cache_reused_and_location_and_date_changes_are_isolated(self):
        loc={'latitude':0,'longitude':0,'timezone':'UTC'};now=datetime(2026,9,9,12,tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as temp:
            first=solar.load(loc,temp,now)
            with patch.object(solar,'calculate_day',side_effect=AssertionError('Cache miss')):
                self.assertEqual(solar.load(loc,temp,now),first)
            second=solar.load({**loc,'longitude':1},temp,now)
            self.assertNotEqual(first['identity'],second['identity'])
            rolled=solar.load(loc,temp,now+timedelta(days=1))
            self.assertEqual(rolled['localDate'],'2026-09-10')
            self.assertEqual(rolled['days'][-1]['date'],'2026-09-11')

    def test_invalid_coordinates_and_corrupt_cache(self):
        for raw in [None,{}, {'latitude':True,'longitude':0}, {'latitude':91,'longitude':0}, {'latitude':0,'longitude':float('nan')}, {'latitude':0,'longitude':0,'timezone':'Bad/Zone'}]:
            with self.subTest(raw=raw),self.assertRaises(solar.PrayerError):solar.location(raw)
        with tempfile.TemporaryDirectory() as temp:
            loc={'latitude':0,'longitude':0,'timezone':'UTC'};now=datetime(2026,9,9,12,tzinfo=timezone.utc)
            solar.load(loc,temp,now)
            next(Path(temp).glob('solar-*.json')).write_text('{bad')
            self.assertEqual(len(solar.load(loc,temp,now)['days']),3)

if __name__=='__main__':unittest.main()
