#!/usr/bin/env python3
"""Install this checkout into the current user's Omarchy plugin directory."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import secrets
import shutil
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ID = 'salah.prayer-times'


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def atomic_write(path, data):
    """Replace a config file without opening its destination for writing."""
    path = Path(path)
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    temporary = None
    temporary_fd = None

    def verify_directory():
        opened = os.fstat(directory_fd)
        named = path.parent.stat(follow_symlinks=False)
        if (not stat.S_ISDIR(opened.st_mode) or opened.st_uid != os.geteuid()
                or opened.st_mode & 0o022 or not os.path.samestat(opened, named)):
            raise RuntimeError('The shell configuration directory changed or is not owned and protected by this user.')

    def verify_file(fd):
        opened = os.fstat(fd)
        named = os.stat(temporary, dir_fd=directory_fd, follow_symlinks=False)
        if (not stat.S_ISREG(opened.st_mode) or opened.st_uid != os.geteuid()
                or opened.st_nlink != 1 or stat.S_IMODE(opened.st_mode) != 0o600
                or not os.path.samestat(opened, named)):
            raise RuntimeError('The temporary shell configuration file changed or is unsafe.')

    try:
        verify_directory()
        for _ in range(100):
            candidate = f'.{path.name}.salah-{secrets.token_hex(16)}.tmp'
            try:
                temporary_fd = os.open(candidate,
                                       os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                                       0o600, dir_fd=directory_fd)
            except FileExistsError:
                continue
            temporary = candidate
            break
        else:
            raise FileExistsError('Could not create an exclusive temporary shell configuration file.')

        with os.fdopen(temporary_fd, 'wb') as stream:
            temporary_fd = None  # The stream owns the descriptor from here.
            verify_file(stream.fileno())
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
            verify_directory()
            verify_file(stream.fileno())
            # Both names are relative to the checked directory descriptor.
            # Replacing a destination symlink replaces the link, not its target.
            os.replace(temporary, path.name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
            temporary = None
            os.fsync(directory_fd)
    finally:
        if temporary_fd is not None:
            os.close(temporary_fd)
        try:
            if temporary is not None:
                try:
                    os.unlink(temporary, dir_fd=directory_fd)
                except FileNotFoundError:
                    pass
        finally:
            os.close(directory_fd)


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
                atomic_write(shellfile,(json.dumps(config,indent=2)+'\n').encode('utf-8'))
                run('omarchy-shell','shell','reloadConfig')
            else:
                run('omarchy','plugin','enable',PLUGIN_ID)
        except Exception:
            if destination.exists(): shutil.rmtree(destination)
            if had_plugin: shutil.copytree(backups/'plugin',destination)
            atomic_write(shellfile,old_shell)
            subprocess.run(['omarchy-shell','shell','rescanPlugins'],capture_output=True)
            subprocess.run(['omarchy-shell','shell','reloadConfig'],capture_output=True)
            raise
    print('Installed Salah. Open the mosque → gear to manage location and reminders.')
    print('Backup:',backups)


if __name__=='__main__': main()
