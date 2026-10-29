#!/usr/bin/env python3
"""Native Latin/Romance word families. English glosses never determine membership.

Only recorded origin edges establish historical links. Identical native spellings
are a separate, explicitly labelled relationship, never evidence of shared origin.
"""
from collections import defaultdict, deque
import hashlib
import itertools
import json
from pathlib import Path
import sqlite3
import unicodedata
import zipfile

LANGUAGES = {'la': 'lat', 'es': 'spa', 'fr': 'fra'}
ENGLISH = {'eng', 'enm', 'ang', 'en'}

def key(value):
    return ''.join(c for c in unicodedata.normalize('NFD', value) if not unicodedata.combining(c)).casefold().strip()

def native_key(value):
    # Accents/macrons distinguish words; folding is for search, never identity.
    return unicodedata.normalize('NFC', value).casefold().strip()

def historical_paths(node, edges, limit=8):
    queue = deque([(node, [node])]); seen = {node}; found = {node: [node]}
    while queue and len(seen) <= 256:
        current, path = queue.popleft()
        if current[0] == 'lat' or len(path) > limit:
            continue
        for parent in sorted(edges.get(current, ())):
            if parent in seen or parent[0] in ENGLISH:
                continue
            seen.add(parent); chain = path + [parent]
            found[parent] = chain
            queue.append((parent, chain))
    return found

def origin_paths(node, edges, limit=8):
    return {n: p for n, p in historical_paths(node, edges, limit).items() if n[0] == 'lat' and n != node}

def build(archive, packs, output):
    edges = defaultdict(set); labels = {}
    with zipfile.ZipFile(archive) as source:
        for line in source.open('etymwn.tsv'):
            a, relation, b = line.decode('utf-8').rstrip('\n\r').split('\t')
            if relation not in ('rel:etymology', 'rel:etymological_origin_of'):
                continue
            if relation == 'rel:etymological_origin_of': a, b = b, a
            child_lang, child = a.split(': ', 1); parent_lang, parent = b.split(': ', 1)
            if child_lang in ENGLISH or parent_lang in ENGLISH:
                continue
            if any(not x or x.startswith(('*', '-')) or x.endswith('-') or len(x) > 80 for x in (child, parent)):
                continue
            child_node = (child_lang, native_key(child)); parent_node = (parent_lang, native_key(parent))
            edges[child_node].add(parent_node)
            labels.setdefault(child_node, child); labels.setdefault(parent_node, parent)
    records = {}; words_by_language = {}
    for code in LANGUAGES:
        words = defaultdict(list)
        with sqlite3.connect(f'file:{packs/f"en-{code}.sqlite"}?mode=ro', uri=True) as db:
            for ident, english, pos, definition, translations in db.execute('SELECT rowid,lemma,pos,definition,translations FROM entry ORDER BY rowid'):
                for word in sorted(set(json.loads(translations))):
                    # Families are vocabulary headwords, not arbitrary phrases or affixes.
                    if not word or len(word) > 80 or any(c.isspace() for c in word) or word.startswith(('*', '-')) or word.endswith('-'):
                        continue
                    node = (code, native_key(word))
                    words[node[1]].append(node)
                    records.setdefault(node, []).append(dict(sourceID=str(ident), headword=word, english=english, pos=pos, definition=definition))
        words_by_language[code] = set(words)
    graph_nodes = set(labels)
    folded_nodes = defaultdict(set)
    for node in graph_nodes: folded_nodes[(node[0], key(node[1]))].add(node)
    # Only a unique accent-insensitive match is allowed, on BOTH sides. No
    # English meaning is used to resolve historical homographs.
    folded_words = defaultdict(set)
    for node in records: folded_words[(node[0], key(node[1]))].add(node)
    native_nodes = {}
    for node in records:
        iso = LANGUAGES[node[0]]; exact = (iso, node[1])
        choices = folded_nodes[(iso, key(node[1]))]
        if exact in graph_nodes:
            native_nodes[node] = exact
        elif len(choices) == 1 and len(folded_words[(node[0], key(node[1]))]) == 1:
            native_nodes[node] = next(iter(choices))
        else:
            native_nodes[node] = exact
    # Resolve attested Latin inflections through an unambiguous local paradigm.
    # The graph is supplemented only when that lemma is a bundled headword.
    with sqlite3.connect(f'file:{packs/"en-la.sqlite"}?mode=ro', uri=True) as db:
        if db.execute("SELECT count(*) FROM sqlite_master WHERE name='lexicalForm'").fetchone()[0]:
            for surface, lemma in db.execute('SELECT surface,min(lemma) FROM lexicalForm GROUP BY surface HAVING count(DISTINCT lemma)=1'):
                child = ('lat', native_key(surface)); parent = ('lat', native_key(lemma))
                if ('la', parent[1]) in records and child != parent:
                    # Latin is a stopping point; canonicalize that anchor later.
                    edges[child].add(parent)
    latin_aliases = {}
    for node in set(labels):
        if node[0] != 'lat' or ('la', node[1]) in records: continue
        parents = {p for p in edges.get(node, ()) if p[0] == 'lat' and ('la', p[1]) in records}
        if len(parents) == 1: latin_aliases[node] = next(iter(parents))
    anchors = defaultdict(dict)
    for node, origin in sorted(native_nodes.items()):
        paths = historical_paths(origin, edges)
        for ancestor, path in paths.items():
            canonical = latin_aliases.get(ancestor, ancestor)
            if canonical != ancestor: path = path + [canonical]
            old = anchors[canonical].get(node)
            if old is None or len(path) < len(old): anchors[canonical][node] = path
    # For each native word pair retain its nearest recorded common ancestor.
    # This prevents distant roots from generating redundant giant families.
    best = {}
    for anchor, descendants in sorted(anchors.items()):
        if len({n[0] for n in descendants}) < 2: continue
        for a, b in itertools.combinations(sorted(descendants), 2):
            if a[0] == b[0]: continue
            score = (len(descendants[a]) + len(descendants[b]), max(len(descendants[a]), len(descendants[b])), anchor)
            if (a, b) not in best or score < best[(a, b)][0]: best[(a, b)] = (score, anchor)
    families = defaultdict(dict); covered_pairs = set()
    for pair, (_, anchor) in sorted(best.items()):
        for node in pair: families[('origin', anchor)][node] = anchors[anchor][node]
        covered_pairs.add(pair)
    spellings = defaultdict(set)
    for node in records: spellings[node[1]].add(node)
    for spelling, nodes in sorted(spellings.items()):
        for a, b in itertools.combinations(sorted(nodes), 2):
            if a[0] == b[0] or (a, b) in covered_pairs: continue
            for node in (a, b): families[('spelling', ('', spelling))][node] = [native_nodes[node]]
    output.mkdir(parents=True, exist_ok=True); target = output/'etymology.sqlite'; target.unlink(missing_ok=True)
    db = sqlite3.connect(target)
    db.executescript('''
      CREATE TABLE family(id TEXT PRIMARY KEY,originLanguage TEXT NOT NULL,originWord TEXT NOT NULL,relationship TEXT NOT NULL,languages TEXT NOT NULL,searchKey TEXT NOT NULL);
      CREATE TABLE member(id TEXT PRIMARY KEY,familyID TEXT NOT NULL,language TEXT NOT NULL,sourceID TEXT NOT NULL,headword TEXT NOT NULL,english TEXT NOT NULL,pos TEXT NOT NULL,definition TEXT NOT NULL,path TEXT NOT NULL);
      CREATE INDEX member_family ON member(familyID,language,headword);
      CREATE INDEX family_order ON family(originWord,id);
    ''')
    pair_counts = defaultdict(int); relationships = defaultdict(int)
    for (kind, anchor), descendants in sorted(families.items()):
        languages = sorted({n[0] for n in descendants})
        if len(languages) < 2: continue
        ident = hashlib.sha256(json.dumps((kind, anchor), ensure_ascii=False).encode()).hexdigest()[:24]
        word = labels.get(anchor, anchor[1])
        # Search is exclusively native: never English glosses or lookup lemmas.
        searchable = key(' '.join([word] + [r['headword'] for n in descendants for r in records[n]]))
        db.execute('INSERT INTO family VALUES(?,?,?,?,?,?)', (ident, anchor[0], word, kind, ','.join(languages), searchable))
        relationships[kind] += 1
        for pair in itertools.combinations(languages, 2): pair_counts['-'.join(pair)] += 1
        for node, path in sorted(descendants.items()):
            for record in records[node]:
                mid = hashlib.sha256((ident + node[0] + record['sourceID'] + record['headword']).encode()).hexdigest()[:24]
                db.execute('INSERT OR IGNORE INTO member VALUES(?,?,?,?,?,?,?,?,?)', (mid, ident, node[0], record['sourceID'], record['headword'], record['english'], record['pos'], record['definition'], json.dumps([f'{lang}: {labels.get((lang, term), term)}' for lang, term in path], ensure_ascii=False)))
    count = db.execute('SELECT count(*) FROM family').fetchone()[0]
    members = db.execute('SELECT count(*) FROM member').fetchone()[0]
    native_words = db.execute('SELECT count(*) FROM (SELECT DISTINCT language,headword FROM member)').fetchone()[0]
    db.commit(); db.execute('VACUUM'); assert db.execute('PRAGMA quick_check').fetchone()[0] == 'ok'; db.close()
    manifest = dict(schemaVersion=2, families=count, members=members, nativeWords=native_words, pairs=dict(pair_counts), relationships=dict(relationships), sha256=hashlib.sha256(target.read_bytes()).hexdigest(), byteCount=target.stat().st_size,
        source='Gerard de Melo · Etymological Wordnet 2013-02-08; Wiktionary contributors', license='CC-BY-SA-3.0',
        method='Any pair of Latin, Spanish and French; nearest recorded common origin, maximum 8 edges; English nodes and meaning joins excluded. Identical native spelling is separately labelled.',
        limitations='Origins are word-level historical evidence, not sense-level proof. Homographs and semantic shifts remain visible as independent dictionary senses. Identical spelling alone does not establish cognacy. The 2013 source is incomplete.')
    (output/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2)); return manifest

if __name__ == '__main__':
    import argparse
    p=argparse.ArgumentParser(); p.add_argument('--source',type=Path,required=True); p.add_argument('--packs',type=Path,required=True); p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(); build(a.source,a.packs,a.output)
