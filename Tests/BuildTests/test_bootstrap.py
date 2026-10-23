import hashlib
import io
import json
from pathlib import Path
import stat
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Tools'))
from bootstrap import Bootstrap, BuildError, extract_archive, publish_tree, sha256, verify


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='LinguaFranca build test ')
        self.root = Path(self.temporary.name)
        (self.root / 'Documentation').mkdir()
        (self.root / 'Documentation/Dependencies.lock.json').write_text('{}')

    def tearDown(self):
        self.temporary.cleanup()

    def test_corrupt_bytes_and_incorrect_size_are_rejected(self):
        file = self.root / 'weights.gguf'
        file.write_bytes(b'correct')
        digest = sha256(file)
        verify(file, digest, 7)
        with self.assertRaises(BuildError):
            verify(file, digest, 8)
        file.write_bytes(b'corrupt')
        with self.assertRaises(BuildError):
            verify(file, digest, 7)

    def test_offline_download_uses_verified_cache_without_network(self):
        bootstrap = Bootstrap(self.root, offline=True)
        data = b'pinned asset'
        spec = {'filename': 'asset.zip', 'sha256': hashlib.sha256(data).hexdigest()}
        cached = bootstrap.cache / 'downloads/asset.zip'
        cached.write_bytes(data)
        with patch('bootstrap.subprocess.run', side_effect=AssertionError('network forbidden')):
            self.assertEqual(bootstrap.download(spec), cached)
            cached.write_bytes(b'wrong')
            with self.assertRaises(BuildError):
                bootstrap.download(spec)
            cached.unlink()
            with self.assertRaises(BuildError):
                bootstrap.download(spec)

    def test_receipt_detects_output_changes_and_missing_files(self):
        bootstrap = Bootstrap(self.root, offline=True)
        output = self.root / 'Vendor/file.swift'
        output.parent.mkdir()
        output.write_text('original')
        bootstrap.remember('dependency', 'version-1', [output.parent])
        self.assertTrue(bootstrap.current('dependency', 'version-1'))
        self.assertFalse(bootstrap.current('dependency', 'version-2'))
        output.write_text('changed')
        self.assertFalse(bootstrap.current('dependency', 'version-1'))
        output.unlink()
        self.assertFalse(bootstrap.current('dependency', 'version-1'))

    def test_framework_archive_preserves_internal_symlinks(self):
        archive = self.root / 'framework.zip'
        with zipfile.ZipFile(archive, 'w') as zip_file:
            zip_file.writestr('llama.framework/Versions/A/llama', b'binary')
            link = zipfile.ZipInfo('llama.framework/llama')
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            zip_file.writestr(link, 'Versions/A/llama')
        output = self.root / 'output'
        extract_archive(archive, output)
        link = output / 'llama.framework/llama'
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.read_bytes(), b'binary')

    def test_zip_paths_and_symlinks_cannot_escape_extraction_directory(self):
        for name, target in [('../escaped', None), ('link', '../../escaped')]:
            archive = self.root / 'unsafe.zip'
            with zipfile.ZipFile(archive, 'w') as zip_file:
                info = zipfile.ZipInfo(name)
                if target:
                    info.create_system = 3
                    info.external_attr = (stat.S_IFLNK | 0o777) << 16
                zip_file.writestr(info, target or 'content')
            with self.assertRaises(BuildError):
                extract_archive(archive, self.root / 'extracted')
        self.assertFalse((self.root / 'escaped').exists())

    def test_tar_cannot_escape_extraction_directory(self):
        archive = self.root / 'unsafe.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            entry = tarfile.TarInfo('../escaped')
            entry.size = 4
            tar.addfile(entry, io.BytesIO(b'data'))
        with self.assertRaises(BuildError):
            extract_archive(archive, self.root / 'extracted')
        self.assertFalse((self.root / 'escaped').exists())

    def test_publication_failure_restores_previous_dependency(self):
        incoming, target = self.root / 'new', self.root / 'Vendor/dependency'
        incoming.mkdir()
        target.mkdir(parents=True)
        (incoming / 'file').write_text('new')
        (target / 'file').write_text('working')
        original_rename = Path.rename

        def fail_incoming(path, destination):
            if path.name == 'incoming':
                raise OSError('simulated interruption')
            return original_rename(path, destination)

        with patch.object(Path, 'rename', fail_incoming):
            with self.assertRaises(OSError):
                publish_tree(incoming, target)
        self.assertEqual((target / 'file').read_text(), 'working')
        publish_tree(incoming, target)
        self.assertEqual((target / 'file').read_text(), 'new')


if __name__ == '__main__':
    unittest.main()
