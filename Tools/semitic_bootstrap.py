"""Additive Semitic asset stage; reuses existing checksum/cache and publication rules."""
import fcntl
import os
import shutil
import sys
import tempfile
from pathlib import Path
from bootstrap import run

def prepare_semitic(bootstrap):
    spec=bootstrap.lock['semiticData']
    scripts=['Tools/prepare_semitic_packs.py','Tools/prepare_syriac_corpus.py','Tools/semitic_bootstrap.py']
    fingerprint=bootstrap.fingerprint(spec,scripts)
    with (bootstrap.cache/'semitic-bootstrap.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if bootstrap.current('semitic-packs',fingerprint):return
        for item in spec['sources']+[spec['corpus']]+spec.get('fonts',[]):bootstrap.download(item)
        with tempfile.TemporaryDirectory(prefix='semitic-',dir=bootstrap.cache/'work') as temporary:
            output=Path(temporary)/'output'
            run([sys.executable,bootstrap.root/scripts[0],'--sources',bootstrap.cache/'downloads','--output',output,'--lock',bootstrap.root/'Documentation/Dependencies.lock.json'],log=bootstrap.cache/'logs/semitic-packs.log')
            target=bootstrap.root/'Resources/LanguagePacks';target.mkdir(parents=True,exist_ok=True)
            paths=[]
            for incoming in sorted(output.iterdir()):
                path=target/incoming.name;staged=path.with_suffix(path.suffix+'.part')
                shutil.copyfile(incoming,staged);os.replace(staged,path);paths.append(path)
            for item in spec.get('fonts',[]):
                path=bootstrap.root/'Resources/Fonts'/item['filename'];path.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(bootstrap.cache/'downloads'/item['filename'],path);paths.append(path)
        bootstrap.remember('semitic-packs',fingerprint,paths)
