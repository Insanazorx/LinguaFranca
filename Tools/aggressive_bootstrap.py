"""Separately pinned Aggressive weights; never acquired by the installed application."""
import json
import os
import shutil
from bootstrap import verify, BuildError

def prepare_aggressive(bootstrap):
    folder=bootstrap.root/'Resources/Models'
    spec=json.loads((folder/'aggressive-model-manifest.json').read_text())
    destination=folder/spec['filename']
    if destination.exists():
        try:
            verify(destination,spec['sha256'],spec['byteCount'])
            print('Aggressive Qwen3.5-2B: verified bundled model',flush=True)
            return
        except BuildError: pass
    cached=bootstrap.download({'filename':spec['filename'],'sha256':spec['sha256'],'byteCount':spec['byteCount'],
        'url':'https://huggingface.co/'+spec['repository']+'/resolve/'+spec['revision']+'/'+spec['downloadFilename']})
    staged=destination.with_suffix('.part')
    shutil.copyfile(cached,staged)
    verify(staged,spec['sha256'],spec['byteCount'])
    os.replace(staged,destination)
