#!/usr/bin/env python3
"""Build read-only, source-traceable Semitic packs. Development machine only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import unicodedata
from urllib.parse import quote

LANGUAGES = {'ar': 'Modern Standard Arabic', 'he': 'Modern Hebrew', 'syc': 'Classical Syriac'}
POS = {'noun':'noun','verb':'verb','adj':'adjective','adv':'adverb','conj':'conjunction','prep':'preposition','pron':'pronoun'}
BLOCKED = {'archaic','obsolete','nonstandard','dialectal','Egyptian','Levantine','Moroccan','Biblical-Hebrew-only'}
ROOT_LETTERS = {
    'ar': dict(zip('ءابتثجحخدذرزسشصضطظعغفقكلمنهوي',['ʾ','ʾ','b','t','th','j','ḥ','kh','d','dh','r','z','s','sh','ṣ','ḍ','ṭ','ẓ','ʿ','gh','f','q','k','l','m','n','h','w','y'])),
    'he': dict(zip('אבגדהוזחטיכלמנסעפצקרשת',['ʾ','b','g','d','h','w','z','ḥ','ṭ','y','k','l','m','n','s','ʿ','p','ṣ','q','r','sh','t'])),
    'syc':dict(zip('ܐܒܓܕܗܘܙܚܛܝܟܠܡܢܣܥܦܨܩܪܫܬ',['ʾ','b','g','d','h','w','z','ḥ','ṭ','y','k','l','m','n','s','ʿ','p','ṣ','q','r','sh','t']))
}
ROOT_LETTERS['he'].update({'ך':'k','ם':'m','ן':'n','ף':'p','ץ':'ṣ'})
ROOT_LETTERS['ar'].update({'أ':'ʾ','إ':'ʾ','آ':'ʾ','ؤ':'ʾ','ئ':'ʾ','ى':'y'})

def consonant_labels(root,code):
    """Letter identifiers for search, not supplied word vowels or a pronunciation."""
    letters=[ROOT_LETTERS[code].get(c) for c in root]
    return '-'.join(letters) if all(letters) else ''

def key(value):
    return ''.join(c for c in unicodedata.normalize('NFD',value) if unicodedata.category(c) != 'Mn').casefold()

def identifier(*parts):
    return hashlib.sha256('\x1f'.join(map(str,parts)).encode()).hexdigest()[:28]

def native(value, code):
    low,high = {'ar':(0x600,0x6ff),'he':(0x590,0x5ff),'syc':(0x700,0x74f)}[code]
    letters = [c for c in value if c.isalpha()]
    return bool(letters) and all(low <= ord(c) <= high for c in letters)

def root_letters(value, code):
    value = key(value)
    letters = ''.join(c for c in value if c.isalpha())
    return letters if 2 <= len(letters) <= 5 and native(letters,code) else None

def roots(record, code):
    candidates = []
    if record['pos'] == 'root': candidates.append(record['word'])
    for template in record.get('etymology_templates',[]):
        name,args = template['name'],template.get('args',{})
        if name in {code+'-rootbox',code+'-root'}:
            candidates.append(' '.join(args.get(str(i),'') for i in range(1,6)))
    for sense in record.get('senses',[]):
        for category in sense.get('categories',[]):
            match = re.search(r'terms belonging to the root (.+)',category.get('name',''))
            if match: candidates.append(match[1])
    # The documented he-conj root parameter, not consonants guessed from spelling.
    if code == 'he':
        for template in record.get('inflection_templates',[]):
            if template['name'] == 'he-conj': candidates.append(template.get('args',{}).get('2',''))
        match = re.search(r'from the root ([\u0590-\u05ff־ -]+)',record.get('etymology_text',''))
        if match: candidates.append(match[1])
    return sorted({r for x in candidates if (r := root_letters(x,code))})

def head(record):
    args = record.get('head_templates',[{}])[0].get('args',{})
    canonical = next((x['form'] for x in record.get('forms',[]) if 'canonical' in x.get('tags',[])),None)
    roman = args.get('tr') or next((x['form'] for x in record.get('forms',[]) if 'romanization' in x.get('tags',[])),'')
    pattern = args.get('pat','')
    if record['pos'] == 'verb':
        if record['lang_code'] == 'he': pattern = {'pa':"Pa'al",'pi':"Pi'el",'pu':"Pu'al",'nif':"Nif'al",'hif':"Hif'il",'huf':"Huf'al",'hit':"Hitpa'el"}.get(args.get('1'),args.get('1',''))
        elif record['lang_code'] == 'ar': pattern = next((x for x in args.get('1','').split('/')[0].split('.') if re.fullmatch('[IVX]+',x)),'')
        else:
            templates = str(record.get('inflection_templates',[]))
            pattern = 'Pe\'al' if 'G-strong' in templates else 'Pa\'el' if 'D-strong' in templates else 'Aphel' if 'C-strong' in templates else ''
    return canonical or args.get('wv') or args.get('head') or record['word'],roman,pattern

SCHEMA = '''
CREATE TABLE entry(lemma TEXT NOT NULL,pos TEXT NOT NULL,senseID TEXT NOT NULL,definition TEXT NOT NULL,translations TEXT NOT NULL,score REAL NOT NULL,provenance TEXT NOT NULL,UNIQUE(lemma,pos,senseID,translations));
CREATE INDEX entry_lookup ON entry(lemma,pos);
CREATE TABLE semRoot(id TEXT PRIMARY KEY,language TEXT,native TEXT,searchKey TEXT,transliteration TEXT,meaning TEXT,source TEXT,etymology TEXT);
CREATE INDEX root_search ON semRoot(searchKey);
CREATE TABLE semLexeme(id TEXT PRIMARY KEY,rootID TEXT,language TEXT,lemma TEXT,normalized TEXT,transliteration TEXT,gloss TEXT,pos TEXT,pattern TEXT,source TEXT,etymology TEXT);
CREATE INDEX lexeme_root ON semLexeme(rootID,id);
CREATE INDEX lexeme_normalized ON semLexeme(normalized);
CREATE TABLE semForm(id TEXT PRIMARY KEY,lexemeID TEXT,rootID TEXT,surface TEXT,normalized TEXT,transliteration TEXT,tags TEXT,status TEXT,source TEXT);
CREATE INDEX form_lexeme ON semForm(lexemeID,id);
CREATE INDEX form_root ON semForm(rootID,id);
CREATE INDEX form_normalized ON semForm(normalized);
CREATE TABLE semExample(id TEXT PRIMARY KEY,lexemeID TEXT,text TEXT,translation TEXT,transliteration TEXT,reference TEXT,source TEXT);
CREATE INDEX example_lexeme ON semExample(lexemeID);
CREATE TABLE semFamily(id TEXT PRIMARY KEY,label TEXT,source TEXT);
CREATE TABLE semRelationship(rootID TEXT,familyID TEXT,evidence TEXT,source TEXT,PRIMARY KEY(rootID,familyID));
CREATE TABLE semCorpusTemplate(id TEXT PRIMARY KEY,text TEXT,reference TEXT,source TEXT,groupID TEXT);
CREATE TABLE semCorpusSlot(templateID TEXT,lexemeID TEXT,formID TEXT,start INTEGER,length INTEGER);
CREATE INDEX corpus_slot_lexeme ON semCorpusSlot(lexemeID,templateID);
CREATE INDEX corpus_slot_template ON semCorpusSlot(templateID,start);
'''

def build(source, destination, code, spec, corpus=None):
    path = destination/f'en-{code}.sqlite'
    path.unlink(missing_ok=True)
    db=sqlite3.connect(path); db.executescript(SCHEMA)
    root_data={}; inherited={}; cross_links=[]
    with source.open() as stream:
        for line in stream:
            record=json.loads(line)
            if record.get('lang_code')!=code: continue
            excluded=BLOCKED|({'Biblical','Medieval','dated'} if code=='he' else set())
            senses=[s for s in record.get('senses',[]) if not s.get('form_of') and not set(s.get('tags',[])).intersection(excluded)]
            if not senses: continue
            pos=POS.get(record['pos'])
            rr=roots(record,code)
            canonical,roman,pattern=head(record)
            if not native(canonical,code) or len(canonical)>90: continue
            url='https://en.wiktionary.org/wiki/'+quote(record['word'],safe='')+'#'+{'ar':'Arabic','he':'Hebrew','syc':'Classical_Syriac'}[code]
            glosses=list(dict.fromkeys(g for s in senses for g in s.get('glosses',[]) if g and len(g)<500))
            gloss='; '.join(glosses[:5])[:600]
            if not gloss: continue
            etymology=record.get('etymology_text','')[:1600]
            root=rr[0] if len(rr)==1 else None
            root_id=identifier(code,root) if root else None
            if root:
                existing=root_data.setdefault(root,{'meaning':gloss,'roman':'','source':url,'etymology':etymology,'explicit':False})
                if record['pos']=='root': existing.update(meaning=gloss,roman=roman,source=url,etymology=etymology,explicit=True)
                elif record['pos']=='verb' and pattern=={'ar':'I','he':"Pa'al",'syc':"Pe'al"}[code] and not existing['explicit'] and not existing.get('baseVerb'):
                    existing.update(meaning=gloss,source=url,etymology=etymology,baseVerb=True)
                for template in record.get('etymology_templates',[]):
                    args=template.get('args',{})
                    if template['name'] in ('inh','der') and args.get('2','').startswith('sem-') and args.get('3','').startswith('*'):
                        family=args['2']+':'+args['3']
                        db.execute('INSERT OR IGNORE INTO semFamily VALUES(?,?,?)',(identifier(family),family,url))
                        db.execute('INSERT OR IGNORE INTO semRelationship VALUES(?,?,?,?)',(root_id,identifier(family),template.get('expansion',''),url))
            if not pos: continue
            lex_id=identifier(code,record['word'],canonical,pos,record.get('etymology_number',''),gloss)
            db.execute('INSERT OR IGNORE INTO semLexeme VALUES(?,?,?,?,?,?,?,?,?,?,?)',(lex_id,root_id,code,canonical,key(canonical),roman,gloss,pos,pattern,url,etymology))
            forms=[{'form':canonical,'tags':['canonical'],'roman':roman}]+record.get('forms',[])
            for form in forms:
                surface=form.get('form',''); tags=form.get('tags',[])
                if not native(surface,code) or len(surface)>100 or set(tags).intersection(BLOCKED|{'romanization','class','error-unrecognized-form','table-tags','inflection-template','noun-from-verb'}): continue
                # Source-published forms only. No app-generated root-pattern combinations.
                db.execute('INSERT OR IGNORE INTO semForm VALUES(?,?,?,?,?,?,?,?,?)',(identifier(lex_id,surface,','.join(sorted(tags))),lex_id,root_id,surface,key(surface),form.get('roman',''),json.dumps(sorted(tags)),'attested',url))
                if root and 'noun-from-verb' in tags: inherited.setdefault(key(surface),set()).add(root)
            # Explicit derived lexemes can inherit a root only when the source names them.
            if root:
                for form in record.get('forms',[]):
                    if 'noun-from-verb' in form.get('tags',[]): inherited.setdefault(key(form['form']),set()).add(root)
                for derived in record.get('derived',[]): inherited.setdefault(key(derived.get('word','')),set()).add(root)
            for sense in senses:
                for example in sense.get('examples',[]):
                    text=example.get('text','').split('\n')[0].strip()
                    if example.get('ref') and native(text,code) and 2<=len(text.split())<=75:
                        db.execute('INSERT OR IGNORE INTO semExample VALUES(?,?,?,?,?,?,?)',(identifier(lex_id,text),lex_id,text,example.get('english',example.get('translation',''))[:1400],example.get('roman','')[:1400],example['ref'][:600],url))
                # English concept index from explicit glosses / linked dictionary concepts.
                concepts=set()
                for g in sense.get('glosses',[]):
                    clean=re.sub(r'\([^)]*\)','',g)
                    for value in re.split(r'[,;]',clean):
                        value=value.strip().rstrip('.').removeprefix('to ')
                        if re.fullmatch(r'[A-Za-z]+(?:[ -][A-Za-z]+){0,2}',value) and len(value)<55: concepts.add(value.lower())
                for concept in sorted(concepts):
                    provenance=json.dumps({'source':'Kaikki / English Wiktionary','url':url,'license':'CC-BY-SA-4.0','revision':spec['extractionDate']},ensure_ascii=False)
                    db.execute('INSERT OR IGNORE INTO entry VALUES(?,?,?,?,?,?,?)',(concept,pos,lex_id,'; '.join(sense.get('glosses',[]))[:600],json.dumps([canonical],ensure_ascii=False),1,provenance))
    # Explicit derivative links and only unambiguous root assignments.
    for normalized,roots_set in sorted(inherited.items()):
        if len(roots_set)==1:
            root_id=identifier(code,next(iter(roots_set)))
            db.execute('UPDATE semLexeme SET rootID=? WHERE normalized=? AND rootID IS NULL',(root_id,normalized))
    db.execute('UPDATE semForm SET rootID=(SELECT rootID FROM semLexeme WHERE id=semForm.lexemeID)')
    for root,info in sorted(root_data.items()):
        root_id=identifier(code,root)
        native_root=' '.join(root)
        # Transliteration can be absent; do not synthesize a pronunciation.
        derivatives=' '.join(x[0]+' '+x[1] for x in db.execute('SELECT gloss,transliteration FROM semLexeme WHERE rootID=? ORDER BY id',(root_id,)))
        labels=consonant_labels(root,code)
        search=key(root+' '+native_root+' '+info['meaning']+' '+info['roman']+' '+derivatives+' '+labels+' '+labels.replace('-','')+' '+labels.replace('-',' '))
        roman=info['roman'] or (labels+' (consonant letters)' if labels else '')
        db.execute('INSERT INTO semRoot VALUES(?,?,?,?,?,?,?,?)',(root_id,code,native_root,search,roman,info['meaning'],info['source'],info['etymology']))
    db.execute('DELETE FROM semRelationship WHERE rootID NOT IN (SELECT id FROM semRoot)')
    if corpus:
        from prepare_syriac_corpus import import_corpus
        import_corpus(db,corpus[0],corpus[1])
    db.commit(); db.execute('VACUUM')
    counts={t:db.execute('SELECT count(*) FROM '+t).fetchone()[0] for t in ('entry','semRoot','semLexeme','semForm','semExample')}
    assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
    db.close()
    manifest={'id':'en-'+code,'languageCode':code,'displayName':LANGUAGES[code],'version':'kaikki-'+spec['extractionDate']+'-semitic1','schemaVersion':1,'lexiconDatabaseName':path.name,
        'supportedFeatures':['semitic-roots','source-recorded-morphology','referenced-examples','rtl'],
        'licenseMetadata':{'source':'Kaikki / English Wiktionary','sourceURL':spec['url'],'sourceSHA256':spec['sha256'],'license':'CC-BY-SA-4.0','databaseSHA256':hashlib.sha256(path.read_bytes()).hexdigest()}}
    if corpus:
        manifest['licenseMetadata'].update(corpusSource='https://github.com/ETCBC/syriac',corpusLicense='CC-BY-NC-4.0',corpusRevision=corpus[1],distributionScope='personal-noncommercial')
    (destination/f'en-{code}.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    return counts

def main():
    p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--lock',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    lock=json.loads(a.lock.read_text()); counts={}
    for spec in lock['semiticData']['sources']:
        path=a.sources/spec['filename']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],'Source checksum mismatch'
        corpus=lock['semiticData'].get('corpus')
        counts[spec['languageCode']]=build(path,a.output,spec['languageCode'],spec,
            (a.sources/corpus['filename'],corpus['revision']) if corpus and spec['languageCode']=='syc' else None)
    (a.output/'semitic-coverage.json').write_text(json.dumps(counts,indent=2)+'\n')
    print(json.dumps(counts,indent=2))

if __name__=='__main__':main()
