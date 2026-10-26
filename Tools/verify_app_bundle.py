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
    mac=(app/'Contents/Info.plist').exists()
    contents=app/'Contents' if mac else app
    resources=contents/'Resources' if mac else app
    info=plistlib.loads((contents/'Info.plist').read_bytes())
    binary=(contents/'MacOS' if mac else app)/info['CFBundleExecutable']
    assert binary.is_file(), 'App executable missing'
    assert (contents/'Frameworks/llama.framework/llama').is_file(), 'Inference framework missing'
    rpath='@executable_path/../Frameworks' if mac else '@executable_path/Frameworks'
    assert rpath in subprocess.check_output(['otool','-l',str(binary)],text=True), 'Framework search path missing'
    model=json.loads((resources/'Models/model-manifest.json').read_text())
    weight=resources/'Models'/model['filename']
    assert weight.stat().st_size==model['byteCount'], 'Model size mismatch'
    aggressive=json.loads((resources/'Models/aggressive-model-manifest.json').read_text())
    aggressive_weight=resources/'Models'/aggressive['filename']
    assert aggressive_weight.stat().st_size==aggressive['byteCount'], 'Aggressive model size mismatch'
    assert {x.name for x in (resources/'Models').glob('*.gguf')}=={model['filename'],aggressive['filename']}, 'Only authorized mode-specific models may be bundled'
    if args.checksums:assert sha(aggressive_weight)==aggressive['sha256'], 'Aggressive checksum mismatch'
    if args.checksums:assert sha(weight)==model['sha256'], 'Model checksum mismatch'
    packs=resources/'LanguagePacks';languages=[]
    for manifest in sorted(packs.glob('en-*.json')):
        if manifest.name.endswith('.policy.json'):continue
        meta=json.loads(manifest.read_text());languages.append(meta['languageCode'])
        database=packs/meta['lexiconDatabaseName']
        with sqlite3.connect(f'file:{database}?mode=ro',uri=True) as db:
            assert db.execute('pragma quick_check').fetchone()[0]=='ok'
            assert db.execute('select count(*) from entry').fetchone()[0]>1000
            if 'semitic-roots' in meta['supportedFeatures']:
                assert db.execute('select count(*) from semRoot').fetchone()[0]>100
                assert db.execute('select count(*) from semForm').fetchone()[0]>1000
                assert db.execute("select count(*) from semForm where status not in ('attested','generated','unsupported')").fetchone()[0]==0
                if meta['languageCode']=='syc':
                    assert db.execute('select count(*) from semCorpusTemplate').fetchone()[0]>1000
                    assert meta['licenseMetadata']['corpusLicense']=='CC-BY-NC-4.0'
            elif meta['languageCode'] in ('de','ru'):
                assert db.execute('select count(*) from nounForm').fetchone()[0]>1000
                assert db.execute('select count(*) from caseForm').fetchone()[0]>1000
                for pos in ['verb','adjective']:
                    assert db.execute('select count(*) from practiceForm where pos=?',(pos,)).fetchone()[0]>100
            elif 'attested-forms' in meta['supportedFeatures']:
                assert db.execute('SELECT count(*) FROM lexicalForm').fetchone()[0]>1000
        if args.checksums:assert sha(database)==meta['licenseMetadata']['databaseSHA256']
    assert {'de','ru','ar','he','syc','la','es','fr'}.issubset(languages), 'Bundled target languages missing'
    assert (resources/'Fonts/NotoSansSyriac-Regular.ttf').stat().st_size==233516, 'Syriac font missing'
    search=packs/'_dictionary/search.sqlite'
    search_meta=json.loads((packs/'_dictionary/manifest.json').read_text())
    assert search.stat().st_size==search_meta['byteCount'], 'Dictionary search index missing or truncated'
    if args.checksums:assert sha(search)==search_meta['sha256'], 'Dictionary search checksum mismatch'
    with sqlite3.connect(f'file:{search}?mode=ro',uri=True) as dictionary:
        assert dictionary.execute('pragma quick_check').fetchone()[0]=='ok'
        assert dictionary.execute('select count(*) from document').fetchone()[0]==search_meta['recordCount']
        assert set(r[0] for r in dictionary.execute('select language from pack'))==set(languages)
        assert dictionary.execute("select count(*) from search where search match 'garden'").fetchone()[0]>0
    latin=packs/'_latin'
    latin_meta=json.loads((latin/'manifest.json').read_text())
    assert (latin/'etymology.sqlite').stat().st_size==latin_meta['byteCount']
    if args.checksums:assert sha(latin/'etymology.sqlite')==latin_meta['sha256']
    with sqlite3.connect(f"file:{latin/'etymology.sqlite'}?mode=ro",uri=True) as db:
        assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
        assert db.execute('SELECT count(*) FROM family').fetchone()[0]==latin_meta['families']>100
        assert db.execute("SELECT count(*) FROM (SELECT familyID FROM member GROUP BY familyID HAVING count(DISTINCT language)<>3)").fetchone()[0]==0
    english=packs/'_english'
    meta=json.loads((english/'model-manifest.json').read_text())
    for name,digest in meta['files'].items():
        assert (english/name).is_file(), 'English analysis model missing'
        if args.checksums:assert sha(english/name)==digest
    for name in ['THIRD-PARTY-NOTICES.txt','CC-BY-SA-4.0.txt','CC-BY-SA-3.0.txt','ETCBC-LICENSE.txt','Noto-OFL.txt','FSRS-LICENSE.txt']:
        assert (resources/name).is_file(), f'Missing license: {name}'
    speech=resources/'Speech'
    voice=json.loads((speech/'ru-manifest.json').read_text())
    voice_model=speech/'ru'/voice['modelFilename']
    assert voice_model.stat().st_size==voice['modelByteCount'], 'Bundled Russian voice missing'
    assert (speech/'ru/tokens.txt').is_file() and (speech/'ru/espeak-ng-data/phondata').is_file(), 'Russian phonemizer data missing'
    if args.checksums:assert sha(voice_model)==voice['modelSHA256']
    alignment=json.loads((speech/'ru-alignment-manifest.json').read_text())
    for name,digest in alignment['files'].items():
        file=speech/'ru-alignment'/name
        assert file.is_file(), 'Word-tracking model missing'
        if args.checksums:assert sha(file)==digest
    assert {file.name for file in (speech/'ru-alignment').glob('*.onnx')}=={name for name in alignment['files'] if name.endswith('.onnx')}, 'Do not bundle duplicate full-precision alignment models'
    for name in ['sherpa-onnx-APACHE-2.0.txt','onnxruntime-MIT.txt','piper-MIT.txt','espeak-ng-GPL-3.0.txt','Denis-MODEL-CARD.txt','Vosk-MODEL-CARD.txt']:
        assert (speech/'Licenses'/name).is_file(), 'Speech license missing: '+name
    if mac:
        assert not info.get('LSRequiresIPhoneOS',False), 'This must be a native Mac application'
        build_version=subprocess.check_output(['xcrun','vtool','-show-build',str(binary)],text=True)
        assert 'platform MACOS' in build_version and 'MACCATALYST' not in build_version, 'Expected a native macOS executable'
        assert (resources/'LinguaFranca.icns').is_file(), 'Mac app icon missing'
        entitlements=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL))
        assert entitlements.get('com.apple.security.app-sandbox'), 'Mac sandbox must remain enabled'
        assert not entitlements.get('com.apple.security.cs.disable-library-validation'), 'Keep hardened library validation enabled'
        assert not entitlements.get('com.apple.security.network.client'), 'The offline Mac app needs no network entitlement'
        if not entitlements.get('com.apple.security.get-task-allow'):
            def team(path):
                output=subprocess.run(['codesign','-dvv',str(path)],capture_output=True,text=True,check=True).stderr
                return next((line.split('=',1)[1] for line in output.splitlines() if line.startswith('TeamIdentifier=')),None)
            app_team=team(app)
            assert app_team and app_team!='not set' and app_team==team(contents/'Frameworks/llama.framework'), 'Release app and llama framework must have the same Apple signing team'
    else:
        primary=info.get('CFBundleIcons',{}).get('CFBundlePrimaryIcon',{})
        assert primary.get('CFBundleIconName')=='AppIcon', 'iOS application icon is not configured'
        assert (resources/'Assets.car').is_file(), 'Compiled iOS icon catalog missing'
    print(json.dumps({'platform':'macOS' if mac else 'iOS','bundle':info['CFBundleIdentifier'],'model':model['identifier'],'languages':languages,
        'offlineEnglishAnalysis':True,'checksumsVerified':args.checksums,'status':'passed'},indent=2))

if __name__=='__main__':main()
