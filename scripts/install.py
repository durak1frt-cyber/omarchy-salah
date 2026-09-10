#!/usr/bin/env python3
"""Install this checkout into the current user's Omarchy plugin directory."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ID = 'salah.prayer-times'


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replace', help='Replace this existing bar widget, preserving its position')
    args=parser.parse_args()
    if os.geteuid()==0:
        parser.error('Run this as your desktop user, without sudo.')
    # Plugin commands are locale-sensitive in some Omarchy releases.
    os.environ['LC_ALL']='C'
    run('omarchy','plugin','validate',str(ROOT))
    if run('omarchy-shell','shell','ping')!='ok':
        parser.error('The Omarchy shell must be running.')
    cfgroot=Path(os.environ.get('XDG_CONFIG_HOME',Path.home()/'.config'))
    plugins=cfgroot/'omarchy/plugins'
    destination=plugins/PLUGIN_ID
    if destination.is_symlink():
        parser.error('The destination is a symlink; use a regular plugin directory.')
    shellfile=cfgroot/'omarchy/shell.json'
    old_shell=shellfile.read_bytes()
    config=json.loads(old_shell)
    stamp=datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backups=cfgroot/'omarchy/backups'/('salah-'+stamp)
    backups.mkdir(parents=True)
    (backups/'shell.json').write_bytes(old_shell)
    plugins.mkdir(parents=True,exist_ok=True)
    had_plugin=destination.exists()
    if had_plugin:
        shutil.copytree(destination,backups/'plugin')
    # Stage and validate before replacing a live plugin directory.
    with tempfile.TemporaryDirectory(prefix='salah-install-') as temp:
        staged=Path(temp)/PLUGIN_ID
        shutil.copytree(ROOT,staged,ignore=shutil.ignore_patterns('.git','__pycache__','dist','.test-state'))
        run('omarchy','plugin','validate',str(staged))
        try:
            if had_plugin: shutil.rmtree(destination)
            shutil.copytree(staged,destination)
            run('omarchy-shell','shell','rescanPlugins')
            replaced=False
            if args.replace:
                # Only the selected old widget's entry changes; unrelated bar entries survive.
                for section,entries in config.get('bar',{}).get('layout',{}).items():
                    output=[]
                    for entry in entries:
                        eid=entry.get('id') if isinstance(entry,dict) else entry
                        if eid==args.replace:
                            output.append({'id':PLUGIN_ID}); replaced=True
                        elif eid!=PLUGIN_ID:
                            output.append(entry)
                    config['bar']['layout'][section]=output
                if not replaced:
                    raise RuntimeError('The widget requested for replacement is not in the bar layout.')
                temporary=shellfile.with_name('shell.json.salah-tmp')
                temporary.write_text(json.dumps(config,indent=2)+'\n')
                temporary.replace(shellfile)
                run('omarchy-shell','shell','reloadConfig')
            else:
                run('omarchy','plugin','enable',PLUGIN_ID)
        except Exception:
            if destination.exists(): shutil.rmtree(destination)
            if had_plugin: shutil.copytree(backups/'plugin',destination)
            shellfile.write_bytes(old_shell)
            subprocess.run(['omarchy-shell','shell','rescanPlugins'],capture_output=True)
            subprocess.run(['omarchy-shell','shell','reloadConfig'],capture_output=True)
            raise
    print('Installed Salah. Open the mosque → gear to manage location and reminders.')
    print('Backup:',backups)


if __name__=='__main__': main()
