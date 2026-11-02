"""Cross-pack root comparisons. Identical consonants are not proof of cognacy."""
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import sqlite3
import unicodedata

NOTES = Path(__file__).parent/'Data/semitic_learning.json'

def search_key(text):
    text = ''.join(c for c in unicodedata.normalize('NFD', text).casefold() if not unicodedata.combining(c))
    return ''.join(c for c in text.replace('ʕ', "'").replace('ʿ', "'").replace('ʾ', "'").replace('ʔ', "'") if c.isalnum() or c == "'")

def apply_reviewed_links(db, code, notes=None):
    """Attach only a reviewed exact headword/POS/sense; never infer from its spelling."""
    from prepare_semitic_packs import key, identifier, consonant_labels
    notes = notes if notes is not None else json.loads(NOTES.read_text())['families']
    for note in notes:
        root = note['roots'].get(code)
        if not root: continue
        root_id = identifier(code, root)
        for link in note.get('excludedLinks', []):
            if link['language'] != code: continue
            # A reviewed uncertain root link is removed; the dictionary word survives.
            rows=db.execute('SELECT id FROM semLexeme WHERE lemma=? AND pos=? AND gloss=? AND rootID=?',
                            (link['word'],link['pos'],link['gloss'],root_id)).fetchall()
            for (ident,) in rows:
                db.execute('UPDATE semLexeme SET rootID=NULL WHERE id=?',(ident,))
                db.execute('UPDATE semForm SET rootID=NULL WHERE lexemeID=?',(ident,))
        links = [link for link in note.get('links', []) if link['language'] == code]
        for link in links:
            # Vocalized identity prevents dog/rage and other same-consonant homographs merging.
            rows = db.execute('SELECT id,rootID FROM semLexeme WHERE lemma=? AND pos=? AND instr(lower(gloss),?)>0',
                              (link['word'], link['pos'], link['gloss'].lower())).fetchall()
            for ident, existing in rows:
                if existing is not None and existing != root_id: continue
                letters = consonant_labels(root, code)
                source = next((s for s in note['sources'] if '/wiki/' in s and root[0] in s), note['sources'][0])
                db.execute('INSERT OR IGNORE INTO semRoot VALUES(?,?,?,?,?,?,?,?)',
                           (root_id, code, ' '.join(root), key(root+' '+letters+' '+letters.replace('-', '')+' '+note['summary']),
                            letters+' (consonant letters)', note['summary'], source, 'Reviewed lexical association; see comparison sources.'))
                db.execute('UPDATE semLexeme SET rootID=? WHERE id=? AND rootID IS NULL', (root_id, ident))
                db.execute('UPDATE semForm SET rootID=? WHERE lexemeID=? AND rootID IS NULL', (root_id, ident))

def build(packs, output, notes=None):
    from prepare_semitic_packs import consonant_labels
    notes = notes if notes is not None else json.loads(NOTES.read_text())['families']
    roots = {}; origin = defaultdict(list); shapes = defaultdict(list); derivatives = {}
    for code in ['ar','he','syc']:
        path = packs/f'en-{code}.sqlite'
        if not path.exists(): continue
        with sqlite3.connect(path) as db:
            db.row_factory = sqlite3.Row
            for row in db.execute('SELECT r.*,(SELECT count(*) FROM semLexeme l WHERE l.rootID=r.id) AS lexemeCount FROM semRoot r ORDER BY r.id'):
                r = dict(row); r['letters'] = consonant_labels(r['native'].replace(' ', ''), code)
                roots[r['id']] = r
                if r['letters']: shapes[r['letters']].append(r['id'])
            for r in db.execute('SELECT rootID,familyID FROM semRelationship ORDER BY rootID,familyID'):
                if r['rootID'] in roots: origin[r['familyID']].append(r['rootID'])
            for ident, gloss, lemma, roman in db.execute('SELECT rootID,gloss,lemma,transliteration FROM semLexeme WHERE rootID IS NOT NULL ORDER BY id'):
                derivatives.setdefault(ident, []).append(lemma+' '+roman+' '+gloss)
    parent = {r:r for r in roots}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    evidence = []
    def link(ids, basis):
        ids = sorted(set(ids))
        if len({roots[i]['language'] for i in ids}) < 2: return
        for x in ids[1:]: parent[find(x)] = find(ids[0])
        evidence.append((ids, basis))
    for ids in shapes.values(): link(ids, 'consonants')
    for ids in origin.values(): link(ids, 'historical')
    note_roots = []
    for note in notes:
        ids = [ident for ident,r in roots.items() if note['roots'].get(r['language']) == r['native'].replace(' ','')]
        link(ids, 'reviewed'); note_roots.append((ids, note))
    groups = defaultdict(list)
    for ident in roots: groups[find(ident)].append(ident)
    output.parent.mkdir(parents=True, exist_ok=True); output.unlink(missing_ok=True)
    db = sqlite3.connect(output)
    db.executescript('''
      CREATE TABLE family(id TEXT PRIMARY KEY,label TEXT,languages TEXT,basis TEXT,note TEXT,searchKey TEXT);
      CREATE INDEX family_order ON family(label,id);
      CREATE TABLE member(familyID TEXT,rootID TEXT,language TEXT,native TEXT,letters TEXT,meaning TEXT,transliteration TEXT,source TEXT,etymology TEXT,lexemeCount INTEGER,PRIMARY KEY(familyID,rootID));
      CREATE INDEX member_family ON member(familyID,language);
      CREATE INDEX member_root ON member(rootID);
    ''')
    counts = defaultdict(int)
    for ids in sorted(groups.values()):
        ids = sorted(ids); languages = sorted({roots[i]['language'] for i in ids})
        if len(languages) < 2: continue
        ident = hashlib.sha256(('roots-v1:'+','.join(ids)).encode()).hexdigest()[:28]
        reviewed = [n for rr,n in note_roots if set(rr).intersection(ids)]
        note = reviewed[0] if reviewed else {}
        label = note.get('label') or ' / '.join(sorted({roots[i]['letters'] for i in ids if roots[i]['letters']}))
        basis = 'reviewed' if reviewed else 'historical' if any(b == 'historical' and set(rr).issubset(ids) for rr,b in evidence) else 'consonants'
        search = ' '.join([label, note.get('summary','')]+[str(roots[i][k]) for i in ids for k in ['native','letters','meaning']]+[s for i in ids for s in derivatives.get(i,[])])
        # Both readable text and separator-insensitive root search. Identity stays strict.
        db.execute('INSERT INTO family VALUES(?,?,?,?,?,?)',(ident,label,','.join(languages),basis,json.dumps(note,ensure_ascii=False),search.casefold()+' '+search_key(search)))
        for i in ids:
            r=roots[i]
            db.execute('INSERT INTO member VALUES(?,?,?,?,?,?,?,?,?,?)',(ident,i,r['language'],r['native'],r['letters'],r['meaning'],r['transliteration'],r['source'],r['etymology'],r['lexemeCount']))
        counts['families'] += 1; counts['roots'] += len(ids)
        counts['triple' if len(languages)==3 else 'pair'] += 1
        for pair in [('ar','he'),('ar','syc'),('he','syc')]:
            if set(pair).issubset(languages): counts['-'.join(pair)] += 1
    assert db.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
    db.commit(); db.execute('VACUUM'); db.close()
    meta = dict(schemaVersion=1, **counts, sha256=hashlib.sha256(output.read_bytes()).hexdigest())
    output.with_suffix('.json').write_text(json.dumps(meta,indent=2)+'\n')
    return meta
