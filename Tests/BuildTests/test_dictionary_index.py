import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'Tools'))
from prepare_dictionary_index import build,key

class DictionaryIndexTests(unittest.TestCase):
    def test_full_senses_alternatives_forms_and_unicode_are_indexed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);packs=root/'packs';packs.mkdir()
            meta={'languageCode':'de','lexiconDatabaseName':'de.sqlite','licenseMetadata':{}}
            (packs/'en-de.json').write_text(json.dumps(meta))
            db=sqlite3.connect(packs/'de.sqlite')
            db.executescript('CREATE TABLE entry(lemma,pos,senseID,definition,translations); CREATE TABLE nounForm(lemma,surface);')
            db.executemany('INSERT INTO entry VALUES(?,?,?,?,?)',[
                ('light','noun','illumination','visible light',json.dumps(['Licht','Leuchte'])),
                ('light','adjective','weight','not heavy',json.dumps(['leicht'])),
                ('girl','noun','person','young girl',json.dumps(['Mädchen']))])
            db.execute('INSERT INTO nounForm VALUES(?,?)',('Mädchen','Mädchens'));db.commit();db.close()
            manifest=build(packs,root/'search')
            self.assertEqual(manifest['recordCount'],3)
            with sqlite3.connect(root/'search/search.sqlite') as index:
                self.assertEqual(index.execute("SELECT count(*) FROM search WHERE search MATCH 'leuchte'").fetchone()[0],1)
                self.assertEqual(index.execute("SELECT count(*) FROM search WHERE search MATCH 'madchen'").fetchone()[0],1)
                self.assertEqual(index.execute('SELECT lemmaKey FROM nativeForm WHERE key=?',(key('Mädchens'),)).fetchone()[0],key('Mädchen'))
                self.assertEqual(index.execute("SELECT count(*) FROM document WHERE english='light'").fetchone()[0],2)
    def test_search_keys_preserve_originals_and_fold_combining_marks(self):
        self.assertEqual(key('כָּתַבְתִּי'),'כתבתי')
        self.assertEqual(key('Straße'),'strasse')
        self.assertEqual(key('MÄDCHEN'),'madchen')
