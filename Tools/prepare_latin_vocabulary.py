#!/usr/bin/env python3
"""Join recorded etymology paths to licensed lexical senses, never spelling similarity.

Only etymology/origin edges are followed; related/derived-form edges and affixes are
excluded. Families require French and Spanish descendants plus an attested Latin
translation sharing an English lookup lemma. Each member retains its own sense.
"""
from collections import defaultdict,deque
import hashlib
import json
from pathlib import Path
import sqlite3
import unicodedata
import zipfile

def key(value):
    return ''.join(c for c in unicodedata.normalize('NFD',value) if not unicodedata.combining(c)).lower().strip()

def origin_paths(node,edges,limit=8):
    queue=deque([(node,[node])]);seen={node};found={}
    while queue and len(seen)<=256:
        current,path=queue.popleft()
        if len(path)>limit:continue
        for parent in sorted(edges.get(current,())):
            if parent in seen:continue
            seen.add(parent);chain=path+[parent]
            if parent[0]=='lat':found.setdefault(parent,chain)
            else:queue.append((parent,chain))
    return found

def build(archive,packs,output):
    edges=defaultdict(set)
    with zipfile.ZipFile(archive) as source:
        for line in source.open('etymwn.tsv'):
            a,relation,b=line.decode('utf-8').rstrip('\n\r').split('\t')
            if relation not in ('rel:etymology','rel:etymological_origin_of'):continue
            if relation=='rel:etymological_origin_of':a,b=b,a
            child_lang,child=a.split(': ',1);parent_lang,parent=b.split(': ',1)
            # Historical intermediary languages are permitted; unrelated scripts, affixes,
            # reconstructed forms and very long expressions are not inferred as ancestors.
            if not child or not parent or any(x.startswith(('*','-')) or x.endswith('-') or len(x)>80 for x in (child,parent)):continue
            edges[(child_lang,key(child))].add((parent_lang,key(parent)))
    lexicons={}
    for code in ['la','es','fr']:
        words=defaultdict(list)
        with sqlite3.connect(f'file:{packs/f"en-{code}.sqlite"}?mode=ro',uri=True) as db:
            for ident,english,pos,sense,definition,translations in db.execute('SELECT rowid,lemma,pos,senseID,definition,translations FROM entry ORDER BY rowid'):
                for word in json.loads(translations):
                    words[key(word)].append(dict(sourceID=str(ident),headword=word,english=english,pos=pos,definition=definition,senseID=sense))
        lexicons[code]=words
    families={}
    # A recorded Latin ancestor can be an accusative or another attested inflection.
    # Resolve it only through a unique UniMorph lemma; never guess by removing endings.
    latin_forms={}
    with sqlite3.connect(f'file:{packs/"en-la.sqlite"}?mode=ro',uri=True) as db:
        if db.execute("SELECT count(*) FROM sqlite_master WHERE name='lexicalForm'").fetchone()[0]:
            for surface,lemma in db.execute('SELECT surfaceKey,min(lemmaKey) FROM lexicalForm GROUP BY surfaceKey HAVING count(DISTINCT lemmaKey)=1'):
                latin_forms[surface]=lemma
    for code,iso in [('es','spa'),('fr','fra')]:
        for word,records in sorted(lexicons[code].items()):
            for root,path in origin_paths((iso,word),edges).items():
                canonical=root[1] if root[1] in lexicons['la'] else latin_forms.get(root[1],root[1])
                latin=lexicons['la'].get(canonical,[])
                if canonical != root[1]:path=path+[('lat',canonical+' [attested lemma]')]
                for record in records:
                    ancestors=[r for r in latin if r['english']==record['english'] and r['pos']==record['pos']]
                    if not ancestors:continue
                    # Distinct Latin/English concepts never collapse just because an
                    # unaccented etymology node has the same spelling (liber/līber).
                    group_key=(canonical,record['english'],record['pos'])
                    family=families.setdefault(group_key,dict(latin=ancestors[0]['headword'],english=record['english'],pos=record['pos'],members={}))
                    family['members'][(code,record['sourceID'],record['headword'])]=dict(language=code,**record,path=[f'{lang}: {term}' for lang,term in path])
                    for ancestor in ancestors:
                        family['members'][('la',ancestor['sourceID'],ancestor['headword'])]=dict(language='la',**ancestor,path=[f"lat: {ancestor['headword']}"])
    output.mkdir(parents=True,exist_ok=True);target=output/'etymology.sqlite';target.unlink(missing_ok=True)
    db=sqlite3.connect(target)
    db.executescript('''
      CREATE TABLE family(id TEXT PRIMARY KEY,latin TEXT NOT NULL,english TEXT NOT NULL,pos TEXT NOT NULL,searchKey TEXT NOT NULL);
      CREATE TABLE member(id TEXT PRIMARY KEY,familyID TEXT NOT NULL,language TEXT NOT NULL,sourceID TEXT NOT NULL,headword TEXT NOT NULL,english TEXT NOT NULL,pos TEXT NOT NULL,definition TEXT NOT NULL,path TEXT NOT NULL);
      CREATE INDEX member_family ON member(familyID,language,headword);
      CREATE INDEX family_order ON family(english,latin,id);
    ''')
    for group,family in sorted(families.items()):
        members=list(family['members'].values())
        if not {'la','es','fr'}.issubset({m['language'] for m in members}):continue
        ident=hashlib.sha256(json.dumps(group).encode()).hexdigest()[:24]
        searchable=key(' '.join([family['latin'],family['english']]+[m['headword'] for m in members]))
        db.execute('INSERT INTO family VALUES(?,?,?,?,?)',(ident,family['latin'],family['english'],family['pos'],searchable))
        for member in sorted(members,key=lambda m:(m['language'],m['headword'],m['sourceID'])):
            mid=hashlib.sha256((ident+member['language']+member['sourceID']+member['headword']).encode()).hexdigest()[:24]
            db.execute('INSERT INTO member VALUES(?,?,?,?,?,?,?,?,?)',(mid,ident,member['language'],member['sourceID'],member['headword'],member['english'],member['pos'],member['definition'],json.dumps(member['path'],ensure_ascii=False)))
    count=db.execute('SELECT count(*) FROM family').fetchone()[0]
    members=db.execute('SELECT count(*) FROM member').fetchone()[0]
    db.commit();db.execute('VACUUM');assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok';db.close()
    manifest=dict(schemaVersion=1,families=count,members=members,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),byteCount=target.stat().st_size,
                  source='Gerard de Melo · Etymological Wordnet 2013-02-08; English Wiktionary contributors',license='CC-BY-SA-3.0',
                  method='Recorded etymology edges, maximum 8 nodes; same English lemma and POS; Latin, French and Spanish attested dictionary entries',
                  limitations='Word-level historical links, not sense-level proof. Coverage is incomplete and based on the 2013 extraction. Related meanings may differ; no spelling-based cognates.')
    (output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(manifest,ensure_ascii=False,indent=2));return manifest

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--packs',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();build(a.source,a.packs,a.output)
