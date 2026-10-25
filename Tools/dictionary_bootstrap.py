"""Add a reproducible search catalog without changing the source dictionaries."""
import fcntl
import json
import os
import shutil
import sys
import tempfile
from bootstrap import run

def prepare_dictionary(bootstrap):
    packs=bootstrap.root/'Resources/LanguagePacks'
    sources={p.name:json.loads(p.read_text())['licenseMetadata']['databaseSHA256'] for p in sorted(packs.glob('en-*.json')) if not p.name.endswith('.policy.json')}
    scripts=['Tools/prepare_dictionary_index.py','Tools/dictionary_bootstrap.py']
    fingerprint=bootstrap.fingerprint(sources,scripts)
    with (bootstrap.cache/'dictionary-bootstrap.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if bootstrap.current('dictionary-index',fingerprint):return
        with tempfile.TemporaryDirectory(prefix='dictionary-',dir=bootstrap.cache/'work') as temp:
            output=__import__('pathlib').Path(temp)/'output'
            run([sys.executable,bootstrap.root/scripts[0],'--packs',packs,'--output',output],log=bootstrap.cache/'logs/dictionary-index.log')
            target=packs/'_dictionary';target.mkdir(parents=True,exist_ok=True);paths=[]
            for incoming in output.iterdir():
                path=target/incoming.name;staged=path.with_suffix(path.suffix+'.part');shutil.copyfile(incoming,staged);os.replace(staged,path);paths.append(path)
        bootstrap.remember('dictionary-index',fingerprint,paths)
