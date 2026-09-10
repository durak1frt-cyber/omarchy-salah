#!/usr/bin/env python3
"""Render the marketplace preview from real components using local demo data."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import solar

with tempfile.TemporaryDirectory(prefix='salah-preview-') as temporary:
    temp=Path(temporary)
    for name in ('Commons','Ui'):
        (temp/name).symlink_to(Path('/usr/share/omarchy/shell')/name,target_is_directory=True)
    (temp/'plugin').symlink_to(ROOT,target_is_directory=True)
    location={'latitude':41.0082,'longitude':28.9784,'timezone':'Europe/Istanbul'}
    today=datetime.now(ZoneInfo(location['timezone'])).date()
    timetable={'location':'Istanbul · Demo','timezone':location['timezone'],
        'coordinates':{k:location[k] for k in ('latitude','longitude')},'days':[
            {'date':(today+timedelta(days=n)).isoformat(),'timings':{
                'Fajr':'05:10','Sunrise':'06:35','Dhuhr':'13:10','Asr':'16:40','Maghrib':'19:25','Isha':'20:50'}}
            for n in (-1,0,1)]}
    (temp/'timetable.json').write_text(json.dumps(timetable))
    (temp/'config/salah').mkdir(parents=True)
    (temp/'config/salah/config.json').write_text(json.dumps({'provider':'file','locationMode':'manual',
        'scheduleFile':str(temp/'timetable.json'),'notifications':False,'sound':'off','showQibla':True,'guidanceProfile':'off'}))
    solar.load(location,temp/'state/salah')
    (temp/'shell.qml').write_text((ROOT/'tests/preview.qml').read_text().replace('PREVIEW_PATH',str(ROOT/'preview.png')))
    env={**os.environ,'XDG_CONFIG_HOME':str(temp/'config'),'XDG_STATE_HOME':str(temp/'state')}
    result=subprocess.run(['quickshell','-p',str(temp/'shell.qml'),'--no-color'],env=env,text=True,capture_output=True,timeout=20)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: preview saved' not in output or 'ERROR:' in output:
        print(output);raise SystemExit('Preview render failed')
    print('Rendered',ROOT/'preview.png')
