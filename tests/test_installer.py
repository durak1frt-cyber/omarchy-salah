import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'salah_installer', Path(__file__).parents[1] / 'scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.config_home = self.root / 'config'
        self.omarchy = self.config_home / 'omarchy'
        self.omarchy.mkdir(parents=True)
        self.shellfile = self.omarchy / 'shell.json'
        self.old_shell = b'{"bar":{"layout":{"center":["clock","local.prayer-times"]}}}\n'
        self.shellfile.write_bytes(self.old_shell)
        self.victim = self.root / 'unrelated.txt'
        self.victim.write_bytes(b'Unrelated user file\n')
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source / 'manifest.json').write_text('{"id":"salah.prayer-times"}')
        self.destination = self.omarchy / 'plugins' / installer.PLUGIN_ID
        self.destination.mkdir(parents=True)
        (self.destination / 'old-plugin.txt').write_text('Previous installation')

    def install(self, fail_reload=False):
        def run(*args):
            if args == ('omarchy-shell', 'shell', 'ping'):
                return 'ok'
            if args == ('omarchy-shell', 'shell', 'reloadConfig') and fail_reload:
                self.shellfile.unlink()
                self.shellfile.symlink_to(self.victim)
                raise RuntimeError('Simulated shell reload failure')
            return ''

        with patch.object(installer, 'ROOT', self.source), \
                patch.object(installer, 'run', side_effect=run), \
                patch.object(installer.subprocess, 'run'), \
                patch.dict(os.environ, {'XDG_CONFIG_HOME': str(self.config_home)}), \
                patch('sys.argv', ['install.py', '--replace', 'local.prayer-times']), \
                contextlib.redirect_stdout(io.StringIO()):
            installer.main()

    def test_replace_does_not_follow_predictable_temporary_symlink(self):
        trap = self.omarchy / 'shell.json.salah-tmp'
        trap.symlink_to(self.victim)

        self.install()

        self.assertEqual(self.victim.read_bytes(), b'Unrelated user file\n')
        self.assertTrue(trap.is_symlink())
        self.assertEqual(json.loads(self.shellfile.read_bytes())['bar']['layout']['center'],
                         ['clock', {'id': installer.PLUGIN_ID}])

    def test_rollback_does_not_follow_destination_symlink(self):
        with self.assertRaisesRegex(RuntimeError, 'Simulated shell reload failure'):
            self.install(fail_reload=True)

        self.assertEqual(self.victim.read_bytes(), b'Unrelated user file\n')
        self.assertFalse(self.shellfile.is_symlink())
        self.assertEqual(self.shellfile.read_bytes(), self.old_shell)
        self.assertEqual((self.destination / 'old-plugin.txt').read_text(),
                         'Previous installation')

    def test_temporary_name_collision_does_not_follow_symlink(self):
        trap = self.omarchy / '.shell.json.salah-collision.tmp'
        trap.symlink_to(self.victim)
        with patch.object(installer.secrets, 'token_hex', side_effect=['collision', 'fresh']):
            installer.atomic_write(self.shellfile, b'New configuration\n')
        self.assertEqual(self.victim.read_bytes(), b'Unrelated user file\n')
        self.assertTrue(trap.is_symlink())
        self.assertEqual(self.shellfile.read_bytes(), b'New configuration\n')
        self.assertEqual(stat.S_IMODE(self.shellfile.stat().st_mode), 0o600)

    def test_replacing_hardlinked_destination_does_not_modify_other_link(self):
        other_link = self.root / 'other-shell.json'
        other_link.hardlink_to(self.shellfile)
        installer.atomic_write(self.shellfile, b'New configuration\n')
        self.assertEqual(other_link.read_bytes(), self.old_shell)
        self.assertEqual(self.shellfile.read_bytes(), b'New configuration\n')

    def test_symlinked_destination_directory_is_rejected(self):
        alias = self.root / 'linked-omarchy'
        alias.symlink_to(self.omarchy, target_is_directory=True)
        with self.assertRaises(OSError):
            installer.atomic_write(alias / 'shell.json', b'New configuration\n')
        self.assertEqual(self.shellfile.read_bytes(), self.old_shell)

    def test_group_writable_destination_directory_is_rejected(self):
        self.omarchy.chmod(0o770)
        with self.assertRaisesRegex(RuntimeError, 'directory'):
            installer.atomic_write(self.shellfile, b'New configuration\n')
        self.assertEqual(self.shellfile.read_bytes(), self.old_shell)
        self.assertEqual(list(self.omarchy.glob('.shell.json.salah-*.tmp')), [])

    def test_sync_failure_keeps_original_and_cleans_temporary_file(self):
        with patch.object(installer.os, 'fsync', side_effect=OSError('Simulated disk failure')):
            with self.assertRaisesRegex(OSError, 'Simulated disk failure'):
                installer.atomic_write(self.shellfile, b'New configuration\n')
        self.assertEqual(self.shellfile.read_bytes(), self.old_shell)
        self.assertEqual(list(self.omarchy.glob('.shell.json.salah-*.tmp')), [])

    def test_substituted_temporary_file_is_not_published(self):
        real_fsync = os.fsync

        def replace_temporary(fd):
            real_fsync(fd)
            temporary, = self.omarchy.glob('.shell.json.salah-*.tmp')
            temporary.unlink()
            temporary.symlink_to(self.victim)

        with patch.object(installer.os, 'fsync', side_effect=replace_temporary):
            with self.assertRaisesRegex(RuntimeError, 'temporary'):
                installer.atomic_write(self.shellfile, b'New configuration\n')
        self.assertEqual(self.victim.read_bytes(), b'Unrelated user file\n')
        self.assertEqual(self.shellfile.read_bytes(), self.old_shell)
        self.assertEqual(list(self.omarchy.glob('.shell.json.salah-*.tmp')), [])

    def test_directory_replacement_is_detected_before_publication(self):
        real_fsync = os.fsync
        moved = self.root / 'moved-omarchy'

        def replace_directory(fd):
            real_fsync(fd)
            self.omarchy.rename(moved)
            self.omarchy.mkdir()
            self.shellfile.write_bytes(b'Replacement directory configuration\n')

        with patch.object(installer.os, 'fsync', side_effect=replace_directory):
            with self.assertRaisesRegex(RuntimeError, 'directory'):
                installer.atomic_write(self.shellfile, b'New configuration\n')
        self.assertEqual(self.shellfile.read_bytes(), b'Replacement directory configuration\n')
        self.assertEqual((moved / 'shell.json').read_bytes(), self.old_shell)
        self.assertEqual(list(moved.glob('.shell.json.salah-*.tmp')), [])

    def test_file_is_synced_before_publication_and_directory_after(self):
        real_fsync = os.fsync
        synced = []

        def observe_sync(fd):
            kind = 'directory' if stat.S_ISDIR(os.fstat(fd).st_mode) else 'file'
            synced.append(kind)
            if kind == 'file':
                self.assertEqual(self.shellfile.read_bytes(), self.old_shell)
                temporary, = self.omarchy.glob('.shell.json.salah-*.tmp')
                self.assertEqual(temporary.read_bytes(), b'New configuration\n')
            else:
                self.assertEqual(self.shellfile.read_bytes(), b'New configuration\n')
            real_fsync(fd)

        with patch.object(installer.os, 'fsync', side_effect=observe_sync):
            installer.atomic_write(self.shellfile, b'New configuration\n')
        self.assertEqual(synced, ['file', 'directory'])


if __name__ == '__main__':
    unittest.main()
