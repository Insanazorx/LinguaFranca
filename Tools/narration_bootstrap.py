"""Checksum-pinned, build-time-only offline speech runtime and Russian voice."""
import json
from pathlib import Path
import tempfile
import shutil
from bootstrap import extract_archive, publish_tree, BuildError


def prepare_narration(bootstrap):
    manifest = bootstrap.root/'Resources/Speech/dependencies.json'
    spec = json.loads(manifest.read_text())
    fingerprint = bootstrap.fingerprint(spec, ['Tools/narration_bootstrap.py'])
    if bootstrap.current('russian-narration', fingerprint):
        return
    paths = []
    for asset in spec['archives']:
        archive = bootstrap.download(asset)
        with tempfile.TemporaryDirectory(prefix='speech-', dir=bootstrap.cache/'work') as temporary:
            extract_archive(archive, temporary)
            source = Path(temporary)/asset['archiveRoot']
            if not source.is_dir(): raise BuildError('Invalid speech archive: '+asset['filename'])
            if asset.get('includeFiles'):
                selected=Path(temporary)/'selected';selected.mkdir()
                for name in asset['includeFiles']:shutil.copy2(source/name,selected/name)
                source=selected
            destination = bootstrap.root/asset['vendoredPath']
            publish_tree(source, destination)
            paths.append(destination)
    bootstrap.remember('russian-narration', fingerprint, paths)
    print('Bundled Russian voice and native speech runtime verified.', flush=True)
