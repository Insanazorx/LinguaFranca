#!/usr/bin/env python3
"""Development-only model acquisition. The installed iOS app never downloads resources."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]

def verify(path, manifest):
    if path.stat().st_size != manifest['byteCount']:
        raise ValueError('Model byte count differs from the pinned upstream pointer.')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != manifest['sha256']:
        raise ValueError('SHA-256 mismatch; the model will not be packaged.')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, help='An existing local model; otherwise use the pinned upstream URL.')
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'Resources/Models/model-manifest.json').read_text())
    destination = ROOT / 'Resources/Models' / manifest['filename']
    if args.verify_only or destination.exists():
        verify(destination, manifest)
        print('Verified bundled model:', destination)
        return
    with tempfile.TemporaryDirectory(prefix='linguafranca-model-') as temporary:
        candidate = Path(temporary) / manifest['filename']
        if args.source:
            shutil.copyfile(args.source, candidate)
        else:
            url = f"https://huggingface.co/{manifest['repository']}/resolve/{manifest['revision']}/{manifest['filename']}"
            print('Downloading pinned model from', url, flush=True)
            with urllib.request.urlopen(url, timeout=30) as response, candidate.open('wb') as output:
                shutil.copyfileobj(response, output, 4 * 1024 * 1024)
        verify(candidate, manifest)
        # Copy to a sibling temporary file, then rename atomically, including across volumes.
        sibling = destination.with_suffix('.part')
        try:
            shutil.copyfile(candidate, sibling)
            os.replace(sibling, destination)
        finally:
            sibling.unlink(missing_ok=True)
    print('Packaged verified model:', destination)

if __name__ == '__main__':
    main()
