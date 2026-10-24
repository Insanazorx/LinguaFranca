#!/usr/bin/env python3
"""Restore build dependencies from checksum-pinned sources; never runs in the app."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


class BuildError(RuntimeError):
    pass


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verify(path, digest, size=None):
    path = Path(path)
    if not path.is_file() or (size is not None and path.stat().st_size != size):
        raise BuildError('Missing file or incorrect size: ' + str(path))
    if sha256(path) != digest:
        raise BuildError('SHA-256 mismatch: ' + str(path))


def run(command, cwd=None, log=None, env=None):
    print('  ' + ' '.join(map(str, command)), flush=True)
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('w') as output:
            result = subprocess.run(list(map(str, command)), cwd=cwd, env=env,
                                    stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            tail = '\n'.join(log.read_text(errors='replace').splitlines()[-45:])
            raise BuildError('Command failed; log: ' + str(log) + '\n' + tail)
    else:
        subprocess.run(list(map(str, command)), cwd=cwd, env=env, check=True)


def safe_path(root, name):
    root = Path(root).resolve()
    path = (root / name).resolve()
    if path != root and root not in path.parents:
        raise BuildError('Unsafe archive path: ' + name)
    return path


def extract_archive(archive, destination):
    """Preserve framework symlinks while rejecting paths/links outside extraction root."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as source:
            for item in source.infolist():
                path = safe_path(destination, item.filename)
                mode = item.external_attr >> 16
                if item.is_dir():
                    path.mkdir(parents=True, exist_ok=True)
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                if stat.S_ISLNK(mode):
                    target = source.read(item).decode('utf-8')
                    safe_path(destination, str(path.parent.relative_to(destination.resolve()) / target))
                    path.symlink_to(target)
                else:
                    with source.open(item) as incoming, path.open('wb') as output:
                        shutil.copyfileobj(incoming, output)
                    if mode & 0o777:
                        path.chmod(mode & 0o777)
    else:
        with tarfile.open(archive) as source:
            for item in source.getmembers():
                path = safe_path(destination, item.name)
                if item.issym():
                    safe_path(destination, str(path.parent.relative_to(destination.resolve()) / item.linkname))
                elif item.islnk():
                    safe_path(destination, item.linkname)
                elif not (item.isfile() or item.isdir()):
                    raise BuildError('Unsupported special archive member: ' + item.name)
            if sys.version_info >= (3, 12):
                source.extractall(destination, filter='data')
            else:
                source.extractall(destination)


def publish_tree(source, destination):
    """Replace only a generated dependency, and restore it if publication fails."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.' + destination.name + '-', dir=destination.parent) as tmp:
        temporary = Path(tmp)
        incoming, previous = temporary / 'incoming', temporary / 'previous'
        shutil.copytree(source, incoming, symlinks=True)
        if destination.exists():
            destination.rename(previous)
        try:
            incoming.rename(destination)
        except BaseException:
            if previous.exists():
                previous.rename(destination)
            raise


class Bootstrap:
    def __init__(self, root=ROOT, cache=None, offline=False):
        self.root = Path(root).resolve()
        self.cache = Path(cache or self.root / '.bootstrap').resolve()
        self.offline = offline
        self.lock = json.loads((self.root / 'Documentation/Dependencies.lock.json').read_text())
        for folder in ('downloads', 'receipts', 'work', 'logs'):
            (self.cache / folder).mkdir(parents=True, exist_ok=True)

    def download(self, spec):
        path = self.cache / 'downloads' / spec['filename']
        if path.exists():
            try:
                verify(path, spec['sha256'], spec.get('byteCount'))
                return path
            except BuildError:
                if self.offline:
                    raise
        if self.offline:
            raise BuildError('Offline cache is missing ' + spec['filename'])
        url = spec.get('url')
        if not url:
            # Fixed PyPI version + exact wheel filename + pinned digest; never resolve latest.
            metadata = subprocess.check_output(['curl', '--fail', '--silent', '--show-error',
                '--location', '--proto', '=https', '--connect-timeout', '20', '--max-time', '90',
                'https://pypi.org/pypi/' + spec['package'] + '/' + spec['version'] + '/json'])
            matches = [x for x in json.loads(metadata)['urls'] if x['filename'] == spec['filename']
                       and x['digests']['sha256'] == spec['sha256']]
            if len(matches) != 1:
                raise BuildError('Pinned PyPI wheel unavailable: ' + spec['filename'])
            url = matches[0]['url']
        if not url.startswith('https://'):
            raise BuildError('Downloads require HTTPS')
        partial = path.with_name(path.name + '.part')
        print('Downloading ' + spec['filename'], flush=True)
        command = ['curl', '--fail', '--location', '--show-error', '--proto', '=https',
                   '--retry', '3', '--retry-delay', '2', '--connect-timeout', '20',
                   '--max-time', '1800', '--output', str(partial), url]
        result = subprocess.run(command[:-1] + ['--continue-at', '-', command[-1]])
        if result.returncode in (22, 33, 36):
            # Some CDNs reject HTTP Range. Retry once from the beginning.
            partial.unlink(missing_ok=True)
            result = subprocess.run(command)
        if result.returncode:
            raise BuildError('Download failed; retry to resume: ' + spec['filename'])
        try:
            verify(partial, spec['sha256'], spec.get('byteCount'))
        except BuildError:
            partial.unlink(missing_ok=True)
            raise
        os.replace(partial, path)
        return path

    def fingerprint(self, spec, scripts=()):
        value = {'spec': spec, 'scripts': {name: sha256(self.root / name) for name in scripts}}
        return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()

    def current(self, name, fingerprint):
        try:
            receipt = json.loads((self.cache / 'receipts' / (name + '.json')).read_text())
            if receipt['fingerprint'] != fingerprint:
                return False
            for path, digest in receipt['files'].items():
                verify(self.root / path, digest)
            print(name + ': verified existing files', flush=True)
            return True
        except (OSError, ValueError, KeyError, BuildError):
            return False

    def remember(self, name, fingerprint, paths):
        files = {}
        for path in paths:
            members = sorted(path.rglob('*')) if path.is_dir() else [path]
            for item in members:
                if item.is_file():
                    # macOS /var is an alias of /private/var. Resolve the parent,
                    # preserving a final framework symlink as a required file.
                    canonical = item.parent.resolve() / item.name
                    files[canonical.relative_to(self.root).as_posix()] = sha256(item)
        receipt = {'fingerprint': fingerprint, 'files': files}
        path = self.cache / 'receipts' / (name + '.json')
        temporary = path.with_suffix('.part')
        temporary.write_text(json.dumps(receipt, sort_keys=True, indent=2) + '\n')
        os.replace(temporary, path)

    def grdb(self):
        spec = self.lock['GRDB.swift']
        fingerprint = self.fingerprint(spec)
        if self.current('GRDB', fingerprint):
            return
        archive = self.download({'filename': 'GRDB-v' + spec['version'] + '.tar.gz',
                                 'url': spec['source'], 'sha256': spec['archiveSHA256']})
        with tempfile.TemporaryDirectory(dir=self.cache / 'work') as temporary:
            extract_archive(archive, temporary)
            source = Path(temporary) / ('GRDB.swift-' + spec['commit'])
            destination = self.root / spec['vendoredPath']
            publish_tree(source, destination)
        self.remember('GRDB', fingerprint, [destination])

    def llama(self):
        spec = self.lock['llama.cpp']
        fingerprint = self.fingerprint(spec, ['Tools/bootstrap.py'])
        if self.current('llama', fingerprint):
            return
        binary = self.download({'filename': 'llama-' + spec['version'] + '-xcframework.zip',
                                'url': spec['source'], 'sha256': spec['archiveSHA256']})
        source_spec = spec['simulatorBuild']
        source = self.download({'filename': 'llama-' + spec['version'] + '-source.tar.gz',
                                'url': source_spec['sourceURL'],
                                'sha256': source_spec['sourceArchiveSHA256']})
        if not shutil.which('cmake'):
            if self.offline or not shutil.which('brew'):
                raise BuildError('CMake >= 3.28 is required. Install CMake or Homebrew, then retry.')
            print('Installing missing CMake with Homebrew', flush=True)
            run(['brew', 'install', 'cmake'])
        version = subprocess.check_output(['cmake', '--version'], text=True).splitlines()[0].split()[-1]
        if tuple(int(x) for x in version.split('.')[:2]) < (3, 28):
            raise BuildError('CMake >= 3.28 required; found ' + version)
        # Upstream script deliberately cleans its working directory. Only run in our own cache.
        with tempfile.TemporaryDirectory(prefix='llama-', dir=self.cache / 'work') as temporary:
            temporary = Path(temporary)
            extract_archive(binary, temporary / 'binary')
            extract_archive(source, temporary / 'source')
            source_root = temporary / 'source' / ('llama.cpp-' + spec['version'])
            run(['bash', './build-xcframework.sh', 'ios-sim'], cwd=source_root,
                log=self.cache / 'logs/llama-simulator.log')
            official = temporary / 'binary/build-apple/llama.xcframework'
            simulator = source_root / 'build-apple/llama.xcframework'
            command = ['xcrun', 'xcodebuild', '-create-xcframework']
            for framework in (official, simulator):
                info = plistlib.loads((framework / 'Info.plist').read_bytes())
                for library in info['AvailableLibraries']:
                    directory = framework / library['LibraryIdentifier']
                    command += ['-framework', str(directory / library['LibraryPath'])]
                    symbols = directory / library.get('DebugSymbolsPath', 'dSYMs') / 'llama.dSYM'
                    if symbols.exists():
                        command += ['-debug-symbols', str(symbols)]
            merged = temporary / 'llama.xcframework'
            run(command + ['-output', str(merged)], log=self.cache / 'logs/llama-merge.log')
            shutil.copyfile(source_root / 'LICENSE', merged / 'LICENSE.txt')
            destination = self.root / spec['vendoredPath']
            publish_tree(merged, destination)
        self.remember('llama', fingerprint, [destination])

    def languages(self):
        spec = self.lock['languageData']
        scripts = ['Tools/prepare_language_packs.py', 'Tools/prepare_morphology.py', 'Tools/prepare_practice_forms.py']
        fingerprint = self.fingerprint(spec, scripts)
        if self.current('language-packs', fingerprint):
            return
        with tempfile.TemporaryDirectory(prefix='lexicon-', dir=self.cache / 'work') as temporary:
            temporary = Path(temporary)
            sources, output = temporary / 'sources', temporary / 'output'
            sources.mkdir()
            for item in spec['wikdict'] + spec['morphology'] + spec.get('paradigms', []):
                cached = self.download(item)
                shutil.copyfile(cached, sources / item['filename'])
                if item.get('pythonModule'):
                    extract_archive(cached, sources / 'python')
            run([sys.executable, self.root / scripts[0], '--source', sources, '--output', output],
                log=self.cache / 'logs/language-packs.log')
            run([sys.executable, self.root / scripts[1], '--sources', sources, '--output', output],
                log=self.cache / 'logs/morphology.log')
            run([sys.executable, self.root / scripts[2], '--sources', sources, '--output', output],
                log=self.cache / 'logs/practice-forms.log')
            target = self.root / 'Resources/LanguagePacks'
            target.mkdir(parents=True, exist_ok=True)
            paths = []
            for file in output.iterdir():
                destination = target / file.name
                staged = target / (file.name + '.part')
                shutil.copyfile(file, staged)
                os.replace(staged, destination)
                paths.append(destination)
        self.remember('language-packs', fingerprint, paths)

    def english(self):
        folder = self.root / 'Resources/LanguagePacks/_english'
        spec = json.loads((folder / 'model-manifest.json').read_text())
        fingerprint = self.fingerprint(spec)
        if self.current('english-POS', fingerprint):
            return
        archive = self.download({'filename': 'averaged_perceptron_tagger_eng.zip',
                                'url': spec['source'], 'sha256': spec['archiveSHA256']})
        with tempfile.TemporaryDirectory(dir=self.cache / 'work') as temporary:
            extract_archive(archive, temporary)
            paths = []
            for name, digest in spec['files'].items():
                incoming = Path(temporary) / 'averaged_perceptron_tagger_eng' / name
                verify(incoming, digest)
                destination = folder / name
                shutil.copyfile(incoming, destination.with_suffix('.part'))
                os.replace(destination.with_suffix('.part'), destination)
                paths.append(destination)
        self.remember('english-POS', fingerprint, paths)

    def model(self):
        folder = self.root / 'Resources/Models'
        spec = json.loads((folder / 'model-manifest.json').read_text())
        destination = folder / spec['filename']
        # Existing local weights are useful even before the first bootstrap receipt.
        if destination.exists():
            try:
                verify(destination, spec['sha256'], spec['byteCount'])
                print('Qwen: verified bundled model', flush=True)
                return
            except BuildError:
                print('Qwen: replacing invalid local weights from the verified cache/download', flush=True)
        cached = self.download({'filename': spec['filename'], 'sha256': spec['sha256'],
            'byteCount': spec['byteCount'], 'url': 'https://huggingface.co/' + spec['repository'] +
            '/resolve/' + spec['revision'] + '/' + spec['filename']})
        folder.mkdir(parents=True, exist_ok=True)
        partial = destination.with_suffix('.part')
        shutil.copyfile(cached, partial)
        verify(partial, spec['sha256'], spec['byteCount'])
        os.replace(partial, destination)

    def prepare(self):
        if platform.system() != 'Darwin':
            raise BuildError('Building the native iOS app requires macOS and full Xcode.')
        try:
            subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        except (OSError, subprocess.CalledProcessError) as error:
            raise BuildError('Install full Xcode, open it once, and select its developer tools.') from error
        with (self.cache / 'bootstrap.lock').open('w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise BuildError('Another bootstrap is running for this cache.') from error
            self.grdb()
            self.llama()
            self.languages()
            self.english()
            self.model()
        print('All dependencies and offline app resources verified.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-dir', type=Path)
    parser.add_argument('--offline', action='store_true', help='Use verified cached downloads only.')
    args = parser.parse_args()
    Bootstrap(cache=args.cache_dir, offline=args.offline).prepare()


if __name__ == '__main__':
    try:
        main()
    except (BuildError, subprocess.CalledProcessError) as error:
        print('Bootstrap failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
