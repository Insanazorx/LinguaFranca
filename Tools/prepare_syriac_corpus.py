#!/usr/bin/env python3
"""Import pinned ETCBC 0.9 source forms and immutable corpus frames (CC BY-NC 4.0)."""
import collections
import json
import tarfile
from prepare_semitic_packs import identifier,key,POS

def expand(value):
    for item in value.split(','):
        if '-' in item:
            a,b=map(int,item.split('-'));yield from range(a,b+1)
        else: yield int(item)

def feature(archive,name):
    member=next(m for m in archive.getmembers() if m.name.endswith('/tf/0.9/'+name+'.tf'))
    data=archive.extractfile(member).read().decode().split('\n\n',1)[1]
    result={};node=0
    for line in data.splitlines():
        if not line: continue
        fields=line.split('\t',1)
        if len(fields)==1: node+=1;result[node]=fields[0]
        else:
            nodes=list(expand(fields[0]));node=nodes[-1]
            for n in nodes:result[n]=fields[1]
    return result

def import_corpus(db,archive_path,revision):
    with tarfile.open(archive_path) as archive:
        features={n:feature(archive,n) for n in ('g_cons_utf8','g_cons','lex','gloss','sp','vs','vt','ps','gn','nu','vo','st','trailer','otype','book','chapter','verse','oslots')}
    words=sorted(features['g_cons_utf8'])
    def val(name,n): return features[name].get(n,'')
    pos_map={'verb':'verb','subs':'noun','adjv':'adjective','advb':'adverb','prep':'preposition','conj':'conjunction','prps':'pronoun','prde':'pronoun','prin':'pronoun'}
    stem={'pe':"Pe'al",'pa':"Pa'el",'af':'Aphel'}
    groups=collections.defaultdict(list)
    for n in words:
        pos=pos_map.get(val('sp',n))
        if pos: groups[(val('lex',n),pos,val('vs',n) if pos=='verb' else '')].append(n)
    base_url='https://github.com/ETCBC/syriac/tree/'+revision+'/tf/0.9'
    lexemes={};word_forms={}
    for (lex,pos,vs),members in sorted(groups.items()):
        preferred=[n for n in members if (pos!='verb' or (val('vt',n)=='pf' and val('ps',n)=='third' and val('gn',n)=='m' and val('nu',n)=='sg' and val('vo',n)=='act'))]
        surfaces=collections.Counter(val('g_cons_utf8',n) for n in preferred or members)
        canonical=surfaces.most_common(1)[0][0]
        matches=list(db.execute('SELECT id,rootID,pattern FROM semLexeme WHERE normalized=? AND pos=?',(key(canonical),pos)))
        roots={r[1] for r in matches if r[1]}
        root_id=next(iter(roots)) if len(roots)==1 else None
        compatible=[r for r in matches if not vs or r[2]==stem.get(vs)]
        lex_id=compatible[0][0] if len(compatible)==1 else identifier('etcbc',lex,pos,vs)
        lexemes[(lex,pos,vs)]=lex_id
        gloss=val('gloss',members[0])
        db.execute('INSERT OR IGNORE INTO semLexeme VALUES(?,?,?,?,?,?,?,?,?,?,?)',(lex_id,root_id,'syc',canonical,key(canonical),'ETCBC '+lex,gloss,pos,stem.get(vs,''),base_url,'ETCBC corpus lexeme; original transcription: '+lex))
        for n in members:
            tags=[]
            maps={'vt':{'pf':'perfect','ipf':'imperfect','ptc':'participle','imp':'imperative','inf':'infinitive'},
                  'ps':{'first':'first-person','second':'second-person','third':'third-person'},'gn':{'m':'masculine','f':'feminine'},
                  'nu':{'sg':'singular','pl':'plural','du':'dual'},'vo':{'act':'active','pas':'passive'},'st':{'emph':'emphatic','cst':'construct','abs':'absolute'}}
            for field,mapping in maps.items():
                if val(field,n) in mapping: tags.append(mapping[val(field,n)])
            surface=val('g_cons_utf8',n)
            form_id=identifier(lex_id,surface,','.join(sorted(tags)))
            db.execute('INSERT OR IGNORE INTO semForm VALUES(?,?,?,?,?,?,?,?,?)',(form_id,lex_id,root_id,surface,key(surface),'ETCBC '+val('g_cons',n),json.dumps(sorted(tags)),'attested',base_url+'#word-'+str(n)))
            word_forms[n]=(lex_id,form_id)
        for concept in gloss.removeprefix('to ').split(','):
            concept=concept.strip()
            if concept and len(concept.split())<=3 and all(c.isascii() and (c.isalpha() or c in ' -') for c in concept):
                db.execute('INSERT OR IGNORE INTO entry VALUES(?,?,?,?,?,?,?)',(concept.lower(),pos,lex_id,gloss,json.dumps([canonical],ensure_ascii=False),1,json.dumps({'source':'ETCBC Syriac Corpus 0.9','license':'CC-BY-NC-4.0','revision':revision,'url':base_url})))
    # Exact corpus frames. No mechanically translated word order or guessed slot substitutions.
    # The complete source frame licenses every background component; lexical slots retain
    # the corpus's own features. Future substitution rules require independent review.
    books={};chapters={}
    for n,kind in features['otype'].items():
        if kind in ('book','chapter'):
            slots=list(expand(val('oslots',n)))
            for word in slots:
                if kind=='book': books[word]=val('book',n)
                else: chapters[word]=val('chapter',n)
    frame_count=0
    for n,number in sorted(features['verse'].items()):
        slots=list(expand(val('oslots',n)))
        if not 3<=len(slots)<=90: continue
        text='';spans=[]
        for word in slots:
            surface=val('g_cons_utf8',word);start=len(text.encode('utf-16-le'))//2
            text+=surface+val('trailer',word)
            if word in word_forms:
                spans.append((word_forms[word][0],word_forms[word][1],start,len(surface.encode('utf-16-le'))//2))
        text=text.strip()
        if not text or not spans:continue
        reference=books.get(slots[0],'Corpus')+' '+chapters.get(slots[0],'')+':'+number
        frame_id=identifier('etcbc-0.9-verse',n)
        db.execute('INSERT INTO semCorpusTemplate VALUES(?,?,?,?,?)',(frame_id,text,reference,base_url+'#verse-'+str(n),books.get(slots[0],'')+' '+chapters.get(slots[0],'')))
        for lexeme,form,start,length in spans:
            if start+length<=len(text.encode('utf-16-le'))//2:
                db.execute('INSERT INTO semCorpusSlot VALUES(?,?,?,?,?)',(frame_id,lexeme,form,start,length))
        frame_count+=1
    return {'words':len(words),'lexicalGroups':len(groups),'fixedCorpusFrames':frame_count}
