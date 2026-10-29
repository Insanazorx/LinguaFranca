from collections import defaultdict
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import zipfile
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'Tools'))
from prepare_latin_vocabulary import build,origin_paths
from package_language_addon import package

class LatinVocabularyTests(unittest.TestCase):
    def test_historical_paths_are_bounded_and_cycle_safe(self):
        a=('fra','eau');b=('frm','eau');c=('lat','aqua')
        graph={a:{b},b:{a,c}}
        self.assertEqual(origin_paths(a,graph),{c:[a,b,c]})
        self.assertEqual(origin_paths(a,graph,limit=1),{})

    def test_any_pair_ignores_english_meanings_and_keeps_evidence_separate(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);packs=root/'packs';packs.mkdir();archive=root/'source.zip'
            edges=[('fra: chef','rel:etymology','lat: caput'),('spa: cabo','rel:etymology','lat: caput'),
                   ('fra: parent','rel:etymology','lat: parens'),('spa: pariente','rel:etymology','lat: parens'),
                   ('fra: autre','rel:etymologically_related','lat: caput'),('spa: otro','rel:is_derived_from','lat: caput'),
                   ('fra: isolé','rel:etymology','eng: shared'),('spa: aislado','rel:etymology','eng: shared')]
            with zipfile.ZipFile(archive,'w') as z:z.writestr('etymwn.tsv','\n'.join('\t'.join(e) for e in edges))
            for code,entries in {
                'la':[('head','noun','caput')],
                'fr':[('boss','noun','chef'),('parent','noun','parent'),('gift','noun','don'),('other','adjective','autre'),('isolated','adjective','isolé')],
                'es':[('cape','noun','cabo'),('relative','noun','pariente'),('sir','noun','don'),('other','adjective','otro'),('isolated','adjective','aislado')]
            }.items():
                with sqlite3.connect(packs/f'en-{code}.sqlite') as db:
                    db.execute('CREATE TABLE entry(lemma,pos,senseID,definition,translations)')
                    for en,pos,word in entries:db.execute('INSERT INTO entry VALUES(?,?,?,?,?)',(en,pos,en,en,json.dumps([word])))
            report=build(archive,packs,root/'output')
            self.assertEqual(report['families'],3)
            with sqlite3.connect(root/'output/etymology.sqlite') as db:
                self.assertEqual(db.execute("SELECT count(*) FROM member WHERE headword IN ('autre','otro','isolé','aislado')").fetchone()[0],0)
                family=db.execute("SELECT id FROM family WHERE originWord='caput'").fetchone()[0]
                self.assertEqual({r[0] for r in db.execute('SELECT english FROM member WHERE familyID=?',(family,))},{'head','boss','cape'})
                family=db.execute("SELECT id FROM family WHERE originWord='parens'").fetchone()[0]
                self.assertEqual({r[0] for r in db.execute('SELECT language FROM member WHERE familyID=?',(family,))},{'es','fr'})
                self.assertEqual(db.execute("SELECT relationship FROM family WHERE originWord='don'").fetchone()[0],'spelling')
                self.assertEqual(db.execute("SELECT count(*) FROM family WHERE searchKey LIKE '%cape%'").fetchone()[0],0)
                self.assertEqual(db.execute("SELECT count(*) FROM family WHERE instr(searchKey,'cabo')>0").fetchone()[0],1)

    def test_nearest_origins_and_diacritics_are_not_english_joins(self):
        from prepare_latin_vocabulary import historical_paths, native_key
        self.assertNotEqual(native_key('līber'),native_key('liber'))
        node=('fra','mot'); graph={node:{('eng','word'),('frm','mot')},('frm','mot'):{('lat','muttum')}}
        paths=historical_paths(node,graph)
        self.assertNotIn(('eng','word'),paths)
        self.assertIn(('lat','muttum'),paths)

    def test_addon_export_contains_only_one_pack_and_all_hashes(self):
        import hashlib
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);packs=root/'packs';packs.mkdir()
            metadata=dict(id='en-it',languageCode='it',displayName='Italian',schemaVersion=1,version='test-only',lexiconDatabaseName='en-it.sqlite',writingProfile=dict(script='latin',generationName='Italian',systemLanguageDetection=True),supportedFeatures=[],licenseMetadata=dict(license='test-only'))
            manifest=packs/'en-it.json';manifest.write_text(json.dumps(metadata))
            with sqlite3.connect(packs/'en-it.sqlite') as db:
                db.execute('CREATE TABLE entry(lemma,pos,senseID,definition,translations)')
                db.execute('INSERT INTO entry VALUES(?,?,?,?,?)',('house','noun','fixture','building',json.dumps(['casa'])))
            license=root/'license.txt';license.write_text('Test-only fixture')
            output=package(manifest,root/'Italian.lfpack',license)
            envelope=json.loads((output/'addon.json').read_text())
            self.assertEqual(envelope['metadataFile'],'en-it.json')
            for file in envelope['files']:
                data=(output/file['path']).read_bytes()
                self.assertEqual(file['sha256'],hashlib.sha256(data).hexdigest())
                self.assertEqual(file['byteCount'],len(data))
            with sqlite3.connect(output/'_dictionary/search.sqlite') as db:self.assertEqual(db.execute('SELECT language FROM pack').fetchall(),[('it',)])
            with self.assertRaises(ValueError):package(manifest,output,license)
