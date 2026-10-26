#!/usr/bin/env python3
"""Build an offline search catalog over every bundled lexical record, not replacement candidates."""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import unicodedata


def key(text):
    return ''.join(c for c in unicodedata.normalize('NFD',text) if not unicodedata.combining(c)).lower().replace('ß','ss')


def build(packs, output):
    output.mkdir(parents=True,exist_ok=True)
    target=output/'search.sqlite';target.unlink(missing_ok=True)
    db=sqlite3.connect(target)
    db.executescript('''
      PRAGMA journal_mode=OFF;
      CREATE TABLE document(id INTEGER PRIMARY KEY,language TEXT NOT NULL,kind TEXT NOT NULL,sourceID TEXT NOT NULL,headword TEXT NOT NULL,english TEXT NOT NULL,pos TEXT NOT NULL,definition TEXT NOT NULL,transliteration TEXT NOT NULL,englishKey TEXT NOT NULL,searchText TEXT NOT NULL);
      CREATE TABLE target(documentID INTEGER NOT NULL,key TEXT NOT NULL,PRIMARY KEY(key,documentID));
      CREATE TABLE nativeForm(language TEXT NOT NULL,key TEXT NOT NULL,lemmaKey TEXT NOT NULL,PRIMARY KEY(language,key,lemmaKey));
      CREATE TABLE pack(language TEXT PRIMARY KEY,metadata TEXT NOT NULL,entryCount INTEGER,lexemeCount INTEGER,rootCount INTEGER,formCount INTEGER);
    ''')
    summaries=[]
    for path in sorted(packs.glob('en-*.json')):
        if path.name.endswith('.policy.json'):continue
        meta=json.loads(path.read_text());code=meta['languageCode']
        source=sqlite3.connect(f"file:{packs/meta['lexiconDatabaseName']}?mode=ro",uri=True)
        tables={r[0] for r in source.execute("select name from sqlite_master where type='table'")}
        def add(kind,source_id,headword,english,pos,definition,transliteration='',targets=None):
            english_key=key(english)
            roman=''.join(c for c in transliteration.split('(')[0] if c.isalpha())
            searchable=key(' '.join([headword,english,definition,transliteration,roman]+(targets or [])))
            row=db.execute('INSERT INTO document(language,kind,sourceID,headword,english,pos,definition,transliteration,englishKey,searchText) VALUES(?,?,?,?,?,?,?,?,?,?)',
                (code,kind,str(source_id),headword,english,pos,definition,transliteration,english_key,searchable))
            db.executemany('INSERT OR IGNORE INTO target VALUES(?,?)',[(row.lastrowid,key(t)) for t in (targets or [headword])])
        entry_count=0
        for rowid,lemma,pos,sense,definition,translations in source.execute('SELECT rowid,lemma,pos,senseID,definition,translations FROM entry ORDER BY rowid'):
            words=json.loads(translations)
            add('entry',rowid,words[0] if words else lemma,lemma,pos,definition,targets=words)
            entry_count+=1
        lexeme_count=root_count=form_count=0
        if 'semLexeme' in tables:
            for ident,lemma,gloss,pos,roman in source.execute('SELECT id,lemma,gloss,pos,transliteration FROM semLexeme ORDER BY id'):
                add('lexeme',ident,lemma,gloss,pos,gloss,roman)
                lexeme_count+=1
            for ident,native,meaning,roman in source.execute('SELECT id,native,meaning,transliteration FROM semRoot ORDER BY id'):
                add('root',ident,native,meaning,'root',meaning,roman,targets=[native,native.replace(' ','')])
                root_count+=1
            form_count=source.execute('SELECT count(*) FROM semForm').fetchone()[0]
        else:
            if 'lexicalForm' in tables:
                form_count+=source.execute('SELECT count(*) FROM lexicalForm').fetchone()[0]
                db.executemany('INSERT OR IGNORE INTO nativeForm VALUES(?,?,?)',((code,key(surface),key(lemma)) for lemma,surface in source.execute('SELECT DISTINCT lemma,surface FROM lexicalForm')))
            for table in ['nounForm','caseForm','practiceForm']:
                if table not in tables:continue
                form_count+=source.execute('SELECT count(*) FROM '+table).fetchone()[0]
                db.executemany('INSERT OR IGNORE INTO nativeForm VALUES(?,?,?)',((code,key(surface),key(lemma)) for lemma,surface in source.execute('SELECT DISTINCT lemma,surface FROM '+table)))
        db.execute('INSERT INTO pack VALUES(?,?,?,?,?,?)',(code,json.dumps(meta,ensure_ascii=False),entry_count,lexeme_count,root_count,form_count))
        db.commit();source.close()
        summaries.append(dict(language=code,entries=entry_count,lexemes=lexeme_count,roots=root_count,forms=form_count))
    db.executescript('''
      CREATE INDEX native_form_key ON nativeForm(key,language,lemmaKey);
      CREATE INDEX document_browse ON document(language,englishKey,id);
      CREATE INDEX document_reference ON document(language,kind,sourceID);
      CREATE VIRTUAL TABLE search USING fts5(searchText, content='document', content_rowid='id', tokenize='unicode61 remove_diacritics 2', prefix='2 3 4');
      INSERT INTO search(search) VALUES('rebuild');
      INSERT INTO search(search,rank) VALUES('integrity-check',1);
    ''')
    count=db.execute('SELECT count(*) FROM document').fetchone()[0]
    db.commit();db.execute('VACUUM');assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok';db.close()
    h=hashlib.sha256()
    with target.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):h.update(chunk)
    manifest=dict(schemaVersion=1,recordCount=count,sha256=h.hexdigest(),byteCount=target.stat().st_size,packs=summaries)
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2),flush=True)
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--packs',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();build(a.packs,a.output)
