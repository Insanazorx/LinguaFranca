#!/usr/bin/env python3
"""Export one existing lexical pack as a self-contained, offline .lfpack folder."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from prepare_dictionary_index import build

def package(manifest,output,license_file):
    manifest=Path(manifest);output=Path(output);metadata=json.loads(manifest.read_text())
    code=metadata['languageCode']
    if metadata['id']!='en-'+code or not metadata.get('writingProfile'):
        raise ValueError('Pack needs a language ID and writingProfile before export.')
    if output.exists():raise ValueError('Output already exists: '+str(output))
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.lfpack-',dir=output.parent) as temp:
        stage=Path(temp)/output.name;stage.mkdir()
        shutil.copyfile(manifest,stage/manifest.name)
        shutil.copyfile(manifest.parent/metadata['lexiconDatabaseName'],stage/metadata['lexiconDatabaseName'])
        policy=manifest.with_suffix('.policy.json')
        if policy.exists():shutil.copyfile(policy,stage/policy.name)
        shutil.copyfile(license_file,stage/'LICENSE.txt')
        build(stage,stage/'_dictionary')
        files=[dict(path=p.relative_to(stage).as_posix(),byteCount=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
               for p in sorted(stage.rglob('*')) if p.is_file()]
        (stage/'addon.json').write_text(json.dumps(dict(formatVersion=1,metadataFile=manifest.name,files=files),indent=2)+'\n')
        stage.rename(output)
    return output

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--license',type=Path,required=True)
    a=p.parse_args();print(package(a.manifest,a.output,a.license))
