#!/usr/bin/env python3
"""Exercise actual QML Earth components with local synthetic timetables; no network."""
import argparse,json,os,subprocess,tempfile,sys
from pathlib import Path
from datetime import datetime,timedelta
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
import solar
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'dist/earth-check');parser.add_argument('--software',action='store_true');parser.add_argument('--scale',default='1')
args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='salah-earth-') as tmp:
    temp=Path(tmp)
    for name in ('Commons','Ui'):(temp/name).symlink_to(Path('/usr/share/omarchy/shell')/name,target_is_directory=True)
    (temp/'plugin').symlink_to(ROOT,target_is_directory=True)
    cfg=temp/'config/salah';cfg.mkdir(parents=True)
    now=datetime.now(ZoneInfo('Europe/Istanbul'));today=now.date()
    loc={'latitude':41.0082,'longitude':28.9784,'timezone':'Europe/Istanbul'}
    timetable={'location':'Istanbul · test fixture','timezone':loc['timezone'],'coordinates':{k:loc[k] for k in ('latitude','longitude')},'days':[
        {'date':(today+timedelta(days=n)).isoformat(),'timings':{'Fajr':'04:18','Sunrise':'05:41','Dhuhr':'12:13','Asr':'15:48','Maghrib':'18:35','Isha':'19:52'}} for n in (-1,0,1)]}
    (temp/'timetable.json').write_text(json.dumps(timetable))
    (cfg/'config.json').write_text(json.dumps({'provider':'file','locationMode':'manual','scheduleFile':str(temp/'timetable.json'),'notifications':False,'sound':'off','displayMode':'earth','guidanceProfile':'diyanet','language':'en'}))
    solar.load(loc,temp/'state/salah')
    (temp/'shell.qml').write_text((ROOT/'tests/earth-smoke.qml').read_text().replace('OUTPUT_DIR',str(args.output.resolve())))
    env={**os.environ,'XDG_CONFIG_HOME':str(temp/'config'),'XDG_STATE_HOME':str(temp/'state'),'QT_SCALE_FACTOR':args.scale}
    if args.software:env['QT_QUICK_BACKEND']='software'
    try:
        result=subprocess.run(['quickshell','-p',str(temp/'shell.qml'),'--no-color'],env=env,text=True,capture_output=True,timeout=35)
        output=result.stdout+result.stderr
    except subprocess.TimeoutExpired as exc:
        print((exc.stdout or b'').decode() if isinstance(exc.stdout,bytes) else exc.stdout)
        print((exc.stderr or b'').decode() if isinstance(exc.stderr,bytes) else exc.stderr)
        raise SystemExit('Earth test timed out')
    (args.output/'qml.log').write_text(output)
    failures=[s for s in output.splitlines() if 'FAIL:' in s or 'FAIL!' in s or 'ERROR:' in s or ('WARN scene:' in s and any(t in s for t in ['plugin/','omarchy-salah','Earth','Interval']))]
    if result.returncode or failures or 'PASS: earth, shader' not in output:
        print(output);raise SystemExit('Earth QML test failed')
    for name in ['daylight','sunrise','sunset','night','fallback','turkish-360','arabic-light']:
        assert (args.output/(name+'.png')).exists(),name+' screenshot missing'
    assert json.loads((cfg/'config.json').read_text())['showQibla'] is False, 'Qibla toggle was not persisted'
    print('PASS: Earth native integration; snapshots in',args.output)
