#!/usr/bin/env python3
"""Exercise real settings saves with cached synthetic locations and no network."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import prayer

with tempfile.TemporaryDirectory(prefix='salah-settings-') as temporary:
    temp=Path(temporary)
    for name in ('Commons','Ui'):
        (temp/name).symlink_to(Path('/usr/share/omarchy/shell')/name,target_is_directory=True)
    (temp/'plugin').symlink_to(ROOT,target_is_directory=True)
    (temp/'shell.qml').write_text((ROOT/'tests/settings-smoke.qml').read_text())
    cfg=prayer.settings({'locationMode':'manual','latitude':41.0082,'longitude':28.9784,'notifications':False,'sound':'off'})
    prayer.atomic_json(temp/'config/salah/config.json',cfg)
    detected={'city':'Detected fixture','country':'Test country','latitude':51.5,'longitude':-.12}
    def fetch(config,day):
        times={'Fajr':'04:30','Sunrise':'06:00','Dhuhr':'12:15','Asr':'15:30','Maghrib':'18:15','Isha':'20:00'}
        row=prayer.normalize_day(day,times,'UTC')
        row['coordinates']={k:config[k] for k in ('latitude','longitude')}
        return 'UTC',row
    for mode in ('manual','auto'):
        prayer.load_schedule({**cfg,'locationMode':mode},temp/'state/salah',datetime.now(timezone.utc),fetcher=fetch,locator=lambda:detected)
    # Any accidental live request fails the regression, including IP detection.
    (temp/'sitecustomize.py').write_text('import urllib.request\n'
        'def blocked(*args, **kwargs):\n    raise RuntimeError("Network disabled in settings regression")\n'
        'urllib.request.urlopen = blocked\n')
    env={**os.environ,'XDG_CONFIG_HOME':str(temp/'config'),'XDG_STATE_HOME':str(temp/'state'),'PYTHONPATH':str(temp)}
    try:
        result=subprocess.run(['quickshell','-p',str(temp/'shell.qml'),'--no-color'],env=env,text=True,capture_output=True,timeout=20)
    except subprocess.TimeoutExpired as exc:
        for output in (exc.stdout,exc.stderr):
            if output: print(output.decode() if isinstance(output,bytes) else output)
        raise SystemExit('Settings regression timed out')
    output=result.stdout+result.stderr
    if result.returncode or 'FAIL:' in output or 'ERROR:' in output or 'PASS: immediate settings' not in output:
        print(output);raise SystemExit('Settings regression failed')
    saved=json.loads((temp/'config/salah/config.json').read_text())
    assert saved['countdown'] is True and saved['locationMode']=='manual'
    assert saved['countdownWindow']=='both'
    print('PASS: immediate settings, persisted preferences, automatic/manual location, conditional coloured countdown; no network')
