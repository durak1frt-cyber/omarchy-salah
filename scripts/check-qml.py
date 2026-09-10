#!/usr/bin/env python3
"""Run the real QML components in a temporary window with synthetic data."""
import json
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
omarchy=Path(os.environ.get('OMARCHY_PATH','/usr/share/omarchy'))
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path)
args=parser.parse_args()
with tempfile.TemporaryDirectory(prefix='salah-qml-') as temporary:
    temp=Path(temporary)
    output_dir=args.output.resolve() if args.output else temp
    output_dir.mkdir(parents=True,exist_ok=True)
    for name in ('Commons','Ui'):
        (temp/name).symlink_to(omarchy/'shell'/name,target_is_directory=True)
    (temp/'plugin').symlink_to(root,target_is_directory=True)
    source=(root/'tests/smoke.qml').read_text()
    source=source.replace('SETTINGS_SCREENSHOT_PATH',str(output_dir/'settings.png'))
    source=source.replace('SCREENSHOT_PATH',str(output_dir/'popup.png'))
    (temp/'shell.qml').write_text(source)
    # Keep the graphical regression test fully independent of real locations.
    (temp/'config/salah').mkdir(parents=True)
    (temp/'config/salah/config.json').write_text(json.dumps({'locationMode':'manual'}))
    env={**os.environ,'XDG_CONFIG_HOME':str(temp/'config'),'XDG_STATE_HOME':str(temp/'state')}
    try:
        result=subprocess.run(['quickshell','-p',str(temp/'shell.qml'),'--no-color'],env=env,
                              text=True,capture_output=True,timeout=18)
    except subprocess.TimeoutExpired as exc:
        for output in (exc.stdout,exc.stderr):
            if output: print(output.decode() if isinstance(output,bytes) else output)
        raise SystemExit('QML smoke test timed out')
    output=result.stdout+result.stderr
    expected='PASS: popup opens and settings loads'
    failures=[line for line in output.splitlines() if 'FAIL:' in line or 'ERROR:' in line
              or ('WARN scene:' in line and ('omarchy-salah' in line or 'plugin/' in line))]
    if result.returncode or failures or expected not in output:
        print(output)
        raise SystemExit('QML smoke test failed')
    memory=json.loads((temp/'state/salah/reminders.json').read_text())
    assert memory.get('acknowledged'), 'Acknowledgement was not persisted'
    assert json.loads((temp/'config/salah/config.json').read_text())['showQibla'] is True, 'Qibla was not saved to disk'
    assert (output_dir/'popup.png').exists(), 'Popup did not render'
    assert (output_dir/'settings.png').exists(), 'Settings did not render'
    print('PASS: real QML load, first-run setup, exact colours, shared and persisted acknowledgement, popup and settings rendering')
