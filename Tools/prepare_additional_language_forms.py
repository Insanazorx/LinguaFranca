"""Attach attested UniMorph forms to data-driven language packs; no generated paradigms."""
import hashlib
import json
from pathlib import Path
import sqlite3
import tarfile
import unicodedata

def key(text):
    return ''.join(c for c in unicodedata.normalize('NFD',text) if not unicodedata.combining(c)).lower()

def build(sources,output,spec):
    code=spec['languageCode'];source=spec['morphology'];path=output/f'en-{code}.sqlite'
    db=sqlite3.connect(path)
    db.execute('''CREATE TABLE lexicalForm(lemma TEXT NOT NULL,lemmaKey TEXT NOT NULL,surface TEXT NOT NULL,surfaceKey TEXT NOT NULL,pos TEXT NOT NULL,tags TEXT NOT NULL,form TEXT NOT NULL,tense TEXT NOT NULL,person TEXT NOT NULL,number TEXT NOT NULL,gender TEXT NOT NULL,grammaticalCase TEXT NOT NULL,voice TEXT NOT NULL,source TEXT NOT NULL,license TEXT NOT NULL,UNIQUE(lemmaKey,surface,tags))''')
    wanted={key(t) for (words,) in db.execute('SELECT translations FROM entry') for t in json.loads(words)}
    with tarfile.open(sources/source['filename']) as archive:
        member=next(m for m in archive.getmembers() if m.name.endswith('/'+source['iso']))
        for raw in archive.extractfile(member):
            fields=raw.decode('utf-8').strip().split('\t')
            if len(fields)!=3:continue
            lemma,surface,analysis=fields;normalized=key(lemma)
            if normalized not in wanted or not surface or len(surface)>100:continue
            tags=set(analysis.split(';'));pos='noun' if 'N' in tags or 'PROPN' in tags else 'adjective' if 'ADJ' in tags else 'verb' if any(t.startswith('V') for t in tags) else ''
            if not pos:continue
            form='infinitive' if 'NFIN' in tags else 'converb' if 'V.CVB' in tags else 'participle' if 'V.PTCP' in tags else 'finite' if pos=='verb' and 'IND' in tags else 'inflected'
            tense=next((v for t,v in [('PRS','present'),('PST','past'),('FUT','future')] if t in tags),'')
            number='plural' if 'PL' in tags else 'singular' if 'SG' in tags else ''
            person=next((t for t in ['1','2','3'] if t in tags),'')
            gender=next((v for t,v in [('MASC','masculine'),('FEM','feminine'),('NEUT','neuter')] if t in tags),'')
            case=next((v for t,v in [('NOM','nominative'),('ACC','accusative'),('GEN','genitive'),('DAT','dative'),('ABL','ablative'),('VOC','vocative'),('LOC','locative')] if t in tags),'')
            db.execute('INSERT OR IGNORE INTO lexicalForm VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',(lemma,normalized,surface,key(surface),pos,analysis,form,tense,person,number,gender,case,'passive' if 'PASS' in tags else 'active',source['url'],'CC-BY-SA-3.0'))
    db.executescript('CREATE INDEX lexical_form_lemma ON lexicalForm(lemmaKey,pos,form,tense,person,number); CREATE INDEX lexical_form_surface ON lexicalForm(surfaceKey,lemmaKey);')
    count=db.execute('SELECT count(*) FROM lexicalForm').fetchone()[0];db.commit();db.execute('VACUUM');db.close()
    manifest=output/f'en-{code}.json';metadata=json.loads(manifest.read_text())
    metadata['supportedFeatures']+=['attested-forms','native-form-search']
    metadata['licenseMetadata'].update(databaseSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),morphologySource=source['url'],morphologyLicense='CC-BY-SA-3.0',morphologyAttribution='UniMorph contributors; '+source['iso']+' data, revision '+source['revision'])
    metadata['version']+='-unimorph1'
    manifest.write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
    return count

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--lock',type=Path,required=True)
    a=p.parse_args()
    print(json.dumps({s['languageCode']:build(a.sources,a.output,s) for s in json.loads(a.lock.read_text())['additionalLanguageData'] if s.get('morphology')},indent=2))
