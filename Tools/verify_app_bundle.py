#!/usr/bin/env python3
"""Validate the built artifact before installation, including all offline assets."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import sqlite3
import subprocess

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('app',type=Path)
    parser.add_argument('--checksums',action='store_true')
    args=parser.parse_args();app=args.app
    info=plistlib.loads((app/'Info.plist').read_bytes())
    binary=app/info['CFBundleExecutable']
    assert binary.is_file(), 'App executable missing'
    assert (app/'Frameworks/llama.framework/llama').is_file(), 'Inference framework missing'
    assert '@executable_path/Frameworks' in subprocess.check_output(['otool','-l',str(binary)],text=True), 'Framework search path missing'
    model=json.loads((app/'Models/model-manifest.json').read_text())
    weight=app/'Models'/model['filename']
    assert weight.stat().st_size==model['byteCount'], 'Model size mismatch'
    assert len(list((app/'Models').glob('*.gguf')))==1, 'Bundle only the selected model'
    if args.checksums:assert sha(weight)==model['sha256'], 'Model checksum mismatch'
    packs=app/'LanguagePacks';languages=[]
    for manifest in sorted(packs.glob('en-??.json')):
        meta=json.loads(manifest.read_text());languages.append(meta['languageCode'])
        database=packs/meta['lexiconDatabaseName']
        with sqlite3.connect(f'file:{database}?mode=ro',uri=True) as db:
            assert db.execute('pragma quick_check').fetchone()[0]=='ok'
            assert db.execute('select count(*) from entry').fetchone()[0]>1000
            assert db.execute('select count(*) from nounForm').fetchone()[0]>1000
            assert db.execute('select count(*) from caseForm').fetchone()[0]>1000
            for pos in ['verb','adjective']:
                assert db.execute('select count(*) from practiceForm where pos=?',(pos,)).fetchone()[0]>100
        if args.checksums:assert sha(database)==meta['licenseMetadata']['databaseSHA256']
    assert {'de','ru'}.issubset(languages), 'Initial target languages missing'
    english=packs/'_english'
    meta=json.loads((english/'model-manifest.json').read_text())
    for name,digest in meta['files'].items():
        assert (english/name).is_file(), 'English analysis model missing'
        if args.checksums:assert sha(english/name)==digest
    for name in ['THIRD-PARTY-NOTICES.txt','CC-BY-SA-4.0.txt','CC-BY-SA-3.0.txt']:
        assert (app/name).is_file(), f'Missing license: {name}'
    print(json.dumps({'bundle':info['CFBundleIdentifier'],'model':model['identifier'],'languages':languages,
        'offlineEnglishAnalysis':True,'checksumsVerified':args.checksums,'status':'passed'},indent=2))

if __name__=='__main__':main()
