"""Restore independently versioned Latin, Spanish, French and future WikDict add-ons."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from bootstrap import run

def prepare_additional_languages(bootstrap):
    specs=bootstrap.lock.get('additionalLanguageData',[])
    fingerprint=bootstrap.fingerprint(specs,['Tools/prepare_language_packs.py','Tools/additional_language_bootstrap.py','Tools/prepare_additional_language_forms.py'])
    if bootstrap.current('additional-language-packs',fingerprint):return
    target=bootstrap.root/'Resources/LanguagePacks';target.mkdir(parents=True,exist_ok=True)
    paths=[]
    with tempfile.TemporaryDirectory(prefix='languages-',dir=bootstrap.cache/'work') as temp:
        temp=Path(temp);sources=temp/'sources';sources.mkdir();output=temp/'output'
        for spec in specs:
            shutil.copyfile(bootstrap.download(spec),sources/spec['filename'])
            if spec.get('morphology'):
                item=spec['morphology'];shutil.copyfile(bootstrap.download(item),sources/item['filename'])
        command=[sys.executable,bootstrap.root/'Tools/prepare_language_packs.py','--source',sources,'--output',output]
        for spec in specs:command+=['--language',spec['languageCode']+':'+spec['displayName']]
        run(command,log=bootstrap.cache/'logs/additional-languages.log')
        run([sys.executable,bootstrap.root/'Tools/prepare_additional_language_forms.py','--sources',sources,'--output',output,'--lock',bootstrap.root/'Documentation/Dependencies.lock.json'],log=bootstrap.cache/'logs/additional-forms.log')
        import sqlite3
        report=json.loads((output/'coverage.json').read_text())
        for item in report:
            db_path=output/f"en-{item['language']}.sqlite"
            with sqlite3.connect(db_path) as db:
                if db.execute("SELECT count(*) FROM sqlite_master WHERE name='lexicalForm'").fetchone()[0]:
                    item['attestedForms']=db.execute('SELECT count(*) FROM lexicalForm').fetchone()[0]
            item['bytes']=db_path.stat().st_size
        (output/'coverage.json').write_text(json.dumps(report,indent=2)+'\n')
        for incoming in output.iterdir():
            # Preserve the older German/Russian morphology coverage report.
            name='additional-coverage.json' if incoming.name=='coverage.json' else incoming.name
            path=target/name;staged=path.with_suffix(path.suffix+'.part')
            shutil.copyfile(incoming,staged);os.replace(staged,path);paths.append(path)
    bootstrap.remember('additional-language-packs',fingerprint,paths)
