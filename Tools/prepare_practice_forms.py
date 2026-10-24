#!/usr/bin/env python3
"""Package attested verb and predicate-adjective forms; build-only readers, no guessed translations."""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tarfile
import unicodedata

def key(value):
    return unicodedata.normalize('NFC', value.replace('\u0301', '')).lower()

def open_pack(root, code):
    db = sqlite3.connect(root / f'en-{code}.sqlite')
    db.execute('DROP TABLE IF EXISTS practiceForm')
    db.execute('CREATE TABLE practiceForm(lemma TEXT, pos TEXT, form TEXT, tense TEXT, person TEXT, number TEXT, gender TEXT, surface TEXT, source TEXT, license TEXT, UNIQUE(lemma,pos,form,tense,person,number,gender,surface))')
    return db

def insert(db, lemma, pos, form, surface, source, tense='', person='', number='', gender='', license='CC-BY-SA-3.0'):
    # Multiword/separable verb placement needs a phrase-level grammar adapter.
    if surface.isalpha():
        db.execute('INSERT OR IGNORE INTO practiceForm VALUES(?,?,?,?,?,?,?,?,?,?)',
            (key(lemma),pos,form,tense,person,number,gender,surface,source,license))

def finish(root, code, db, source):
    db.execute('CREATE INDEX practice_form_lookup ON practiceForm(lemma,pos,form,tense,person,number,gender)')
    db.commit(); db.execute('VACUUM')
    counts = dict(db.execute('SELECT pos,count(*) FROM practiceForm GROUP BY pos')); db.close()
    path = root / f'en-{code}.json'; manifest = json.loads(path.read_text())
    manifest['version'] = 'wikdict-2026-06-lf5'
    manifest['supportedFeatures'] += ['attested-verb-forms','attested-predicate-adjectives']
    manifest['licenseMetadata']['practiceMorphologySource'] = source
    manifest['licenseMetadata']['practiceMorphologyLicense'] = 'CC-BY-SA-3.0; CC-BY-SA-4.0 Kaikki/Wiktionary verb paradigms' if code == 'de' else 'CC-BY-SA-3.0'
    manifest['licenseMetadata']['databaseSHA256'] = hashlib.sha256((root / f'en-{code}.sqlite').read_bytes()).hexdigest()
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    return counts

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--sources',type=Path,required=True); parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args(); root=args.output
    de=open_pack(root,'de')
    wanted=set()
    for (translations,) in de.execute("SELECT translations FROM entry WHERE pos IN ('verb','adjective')"):
        wanted.update(key(w) for w in json.loads(translations) if key(w).isalpha())
    archive=args.sources/'unimorph-deu-d226d211.tar.gz'
    with tarfile.open(archive) as tar:
        member=next(m for m in tar if m.name.endswith('/deu'))
        for line in tar.extractfile(member):
            parts=line.decode().strip().split('\t')
            if len(parts)!=3: continue
            lemma,surface,tags=parts; tags=set(tags.split(';'))
            if key(lemma) not in wanted: continue
            if 'ADJ' in tags:
                insert(de,lemma,'adjective','predicative',lemma,'UniMorph/deu')
                if 'CMPR' in tags: insert(de,lemma,'adjective','comparative',surface,'UniMorph/deu')
            elif 'V.PTCP' in tags:
                insert(de,lemma,'verb','converb' if 'PRS' in tags else 'pastParticiple',surface,'UniMorph/deu')
            elif 'V' in tags:
                if 'NFIN' in tags: insert(de,lemma,'verb','infinitive',surface,'UniMorph/deu')
                elif 'IND' in tags and tags.intersection({'PRS','PST'}):
                    insert(de,lemma,'verb','finite',surface,'UniMorph/deu',
                        tense='present' if 'PRS' in tags else 'past', person=next(iter(tags.intersection({'1','2','3'})),''),
                        number='plural' if 'PL' in tags else 'singular')
    # Prefer complete, attested Wiktionary conjugation tables over incomplete UniMorph rows.
    replaced=set()
    with (args.sources/'kaikki-de-verbs-2026-10-21.jsonl').open() as stream:
        for line in stream:
            record=json.loads(line)
            lemma=key(record.get('word',''))
            if record.get('pos')!='verb' or lemma not in wanted: continue
            rows=[]
            for item in record.get('forms',[]):
                tags=set(item.get('tags',[])); surface=item.get('form','')
                if tags.intersection({'archaic','obsolete','dated','rare','nonstandard'}): continue
                if 'indicative' in tags and tags.intersection({'present','past','preterite'}):
                    person={'first-person':'1','second-person':'2','third-person':'3'}
                    who=next((person[x] for x in person if x in tags),'')
                    number='plural' if 'plural' in tags else 'singular' if 'singular' in tags else ''
                    if who and number: rows.append(('finite',surface,'present' if 'present' in tags else 'past',who,number))
                elif 'subjunctive-ii' in tags:
                    person={'first-person':'1','second-person':'2','third-person':'3'}
                    who=next((person[x] for x in person if x in tags),'')
                    number='plural' if 'plural' in tags else 'singular' if 'singular' in tags else ''
                    if who and number: rows.append(('conditional',surface,'',who,number))
                elif 'infinitive' in tags: rows.append(('infinitive',surface,'','',''))
                elif 'participle' in tags: rows.append(('pastParticiple' if 'past' in tags else 'converb',surface,'','',''))
                elif 'auxiliary' in tags and surface in ['haben','sein']: rows.append(('auxiliary',surface,'','',''))
            if not rows: continue
            if lemma not in replaced:
                de.execute("DELETE FROM practiceForm WHERE lemma=? AND pos='verb'",(lemma,));replaced.add(lemma)
            for form,surface,tense,person,number in rows:
                insert(de,lemma,'verb',form,surface,'Kaikki/enwiktionary 2026-10-21',tense,person,number,license='CC-BY-SA-4.0')
    de_counts=finish(root,'de',de,'https://github.com/unimorph/deu/tree/d226d2112d3490d8f04ece10d4538123d4297a39')
    sys.path.insert(0,str((args.sources/'python').resolve()))
    import pymorphy3
    analyzer=pymorphy3.MorphAnalyzer(); ru=open_pack(root,'ru'); wanted=set()
    for pos,translations in ru.execute("SELECT pos,translations FROM entry WHERE pos IN ('verb','adjective')"):
        wanted.update((pos,key(w)) for w in json.loads(translations) if key(w).isalpha())
    for pos,lemma in sorted(wanted):
        for parsed in analyzer.parse(lemma):
            if not parsed.is_known or parsed.normal_form!=lemma: continue
            if pos=='verb' and parsed.tag.POS=='INFN':
                insert(ru,lemma,pos,'infinitive',lemma,'OpenCorpora/pymorphy3')
                for form in parsed.lexeme:
                    tag=form.tag
                    if tag.POS=='VERB' and tag.tense=='pres':
                        insert(ru,lemma,pos,'finite',form.word,'OpenCorpora/pymorphy3',tense='present',person=(tag.person or '').replace('per',''),number='plural' if tag.number=='plur' else 'singular')
                    if tag.POS=='VERB' and tag.tense=='past' and tag.aspect=='impf':
                        insert(ru,lemma,pos,'habitualPast',form.word,'OpenCorpora/pymorphy3',tense='past',number='plural' if tag.number=='plur' else 'singular',gender={'masc':'masculine','femn':'feminine','neut':'neuter'}.get(tag.gender,''))
                    if tag.POS=='VERB' and tag.tense=='past':
                        insert(ru,lemma,pos,'finitePast',form.word,'OpenCorpora/pymorphy3',tense='past',number='plural' if tag.number=='plur' else 'singular',gender={'masc':'masculine','femn':'feminine','neut':'neuter'}.get(tag.gender,''))
                    if tag.POS=='VERB' and tag.tense=='futr':
                        insert(ru,lemma,pos,'finite',form.word,'OpenCorpora/pymorphy3',tense='future',person=(tag.person or '').replace('per',''),number='plural' if tag.number=='plur' else 'singular')
                    if tag.POS=='GRND' and tag.tense=='pres' and tag.aspect=='impf':
                        insert(ru,lemma,pos,'converb',form.word,'OpenCorpora/pymorphy3')
            elif pos=='adjective' and parsed.tag.POS=='ADJF':
                for form in parsed.lexeme:
                    if form.tag.POS=='ADJS':
                        insert(ru,lemma,pos,'predicative',form.word,'OpenCorpora/pymorphy3',number='plural' if form.tag.number=='plur' else 'singular',gender={'masc':'masculine','femn':'feminine','neut':'neuter'}.get(form.tag.gender,''))
    ru_counts=finish(root,'ru',ru,'https://opencorpora.org/?page=downloads')
    coverage=json.loads((root/'coverage.json').read_text())
    for entry in coverage:
        entry['practiceForms']=de_counts if entry['language']=='de' else ru_counts
        entry['bytes']=(root/f"en-{entry['language']}.sqlite").stat().st_size
    (root/'coverage.json').write_text(json.dumps(coverage,indent=2)+'\n')
    print(json.dumps({'de':de_counts,'ru':ru_counts}))

if __name__=='__main__': main()
