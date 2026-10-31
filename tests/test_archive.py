import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from archive import check, create, restore


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'backups').mkdir()
        (self.root / 'data/worlds/world').mkdir(parents=True)
        (self.root / '.env').write_text('ADVERTISED_IP=192.168.1.10\n')
        (self.root / 'data/server.properties').write_text('level-name=world\n')
        (self.root / 'data/worlds/world/level.dat').write_bytes(b'world-before')
        self.backup = self.root / 'backups/test.tar.gz'

    def test_round_trip_keeps_previous_world_and_configuration(self):
        create(self.root, self.backup)
        (self.root / 'data/worlds/world/level.dat').write_bytes(b'world-after')
        (self.root / '.env').write_text('ADVERTISED_IP=203.0.113.10\n')
        restore(self.root, self.backup)
        self.assertEqual((self.root / 'data/worlds/world/level.dat').read_bytes(), b'world-before')
        previous = list((self.root / 'backups').glob('pre-restore-*'))
        self.assertEqual(len(previous), 1)
        self.assertEqual((previous[0] / 'data/worlds/world/level.dat').read_bytes(), b'world-after')
        self.assertIn('203.0.113.10', (previous[0] / '.env').read_text())
        self.assertIn('192.168.1.10', (self.root / '.env').read_text())

    def test_rejects_traversal_links_and_unexpected_files_before_mutation(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('/absolute', tarfile.REGTYPE),
                           ('data/../../escape', tarfile.REGTYPE), ('data/link', tarfile.SYMTYPE),
                           ('data/hardlink', tarfile.LNKTYPE), ('compose.yml', tarfile.REGTYPE),
                           ('data/device', tarfile.CHRTYPE), ('data\\escape', tarfile.REGTYPE)]:
            with self.subTest(name=name, kind=kind):
                with tarfile.open(self.backup, 'w:gz') as archive:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    entry.linkname = '../../escape'
                    archive.addfile(entry)
                with self.assertRaises(ValueError):
                    restore(self.root, self.backup)
                self.assertEqual((self.root / 'data/worlds/world/level.dat').read_bytes(), b'world-before')

    def test_incomplete_backup_does_not_get_published(self):
        (self.root / 'data/worlds/world/level.dat').unlink()
        with self.assertRaises(ValueError):
            create(self.root, self.backup)
        self.assertFalse(self.backup.exists())
        self.assertFalse(list((self.root / 'backups').glob('*.partial')))

    def test_directory_cannot_impersonate_a_world_file(self):
        (self.root / 'data/worlds/world/level.dat').unlink()
        (self.root / 'data/worlds/world/level.dat').mkdir()
        with self.assertRaises(ValueError):
            create(self.root, self.backup)

    def test_existing_partial_is_not_deleted(self):
        partial = self.backup.with_suffix('.gz.partial')
        partial.write_bytes(b'keep-existing-partial')
        with self.assertRaises(FileExistsError):
            create(self.root, self.backup)
        self.assertEqual(partial.read_bytes(), b'keep-existing-partial')

    def test_failed_configuration_install_rolls_back_world_and_config(self):
        create(self.root, self.backup)
        (self.root / 'data/worlds/world/level.dat').write_bytes(b'world-after')
        (self.root / '.env').write_text('KEEP-THIS-CONFIG\n')
        original_rename = Path.rename

        def fail_new_env_once(source, target):
            if source.name == '.env' and source.parent.name.startswith('.restore-'):
                raise OSError('simulated configuration install failure')
            return original_rename(source, target)

        with patch.object(Path, 'rename', fail_new_env_once):
            with self.assertRaises(OSError):
                restore(self.root, self.backup)
        self.assertEqual((self.root / 'data/worlds/world/level.dat').read_bytes(), b'world-after')
        self.assertEqual((self.root / '.env').read_text(), 'KEEP-THIS-CONFIG\n')

    def test_truncated_gzip_is_rejected(self):
        create(self.root, self.backup)
        self.backup.write_bytes(self.backup.read_bytes()[:-8])
        with self.assertRaises((EOFError, OSError, tarfile.TarError)):
            check(self.backup)


if __name__ == '__main__':
    unittest.main()
