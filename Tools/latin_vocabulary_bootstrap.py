from pathlib import Path
import json
import shutil
import sys
import tempfile
from bootstrap import run,publish_tree

def prepare_latin_vocabulary(bootstrap):
    packs=bootstrap.root/'Resources/LanguagePacks'
    spec=bootstrap.lock['latinEtymology']
    inputs=dict(source=spec,packs={code:json.loads((packs/f'en-{code}.json').read_text())['licenseMetadata']['databaseSHA256'] for code in ['la','es','fr']})
    fingerprint=bootstrap.fingerprint(inputs,['Tools/prepare_latin_vocabulary.py','Tools/latin_vocabulary_bootstrap.py'])
    if bootstrap.current('latin-vocabulary',fingerprint):return
    archive=bootstrap.download(spec)
    with tempfile.TemporaryDirectory(prefix='latin-vocab-',dir=bootstrap.cache/'work') as temp:
        output=Path(temp)/'output'
        run([sys.executable,bootstrap.root/'Tools/prepare_latin_vocabulary.py','--source',archive,'--packs',packs,'--output',output],log=bootstrap.cache/'logs/latin-vocabulary.log')
        target=packs/'_latin';publish_tree(output,target)
    bootstrap.remember('latin-vocabulary',fingerprint,[target])
