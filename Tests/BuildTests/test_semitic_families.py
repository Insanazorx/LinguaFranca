import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Tools'))
from prepare_semitic_packs import SCHEMA, identifier, consonant_labels
from prepare_semitic_families import build, search_key, apply_reviewed_links

class SemiticFamilyTests(unittest.TestCase):
    def test_separator_aliases_do_not_change_root_identity(self):
        self.assertEqual(search_key('K - L B'),'klb')
        self.assertEqual(search_key('ʿ-b-d'),search_key("' b d"))
        self.assertEqual(search_key('ṣ-l-ḥ'),search_key('s l h'))
        self.assertNotEqual(consonant_labels('صلح','ar'),consonant_labels('سلح','ar'))

    def test_pairs_triples_keep_all_native_languages_and_label_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            for code,roots in [('ar',['كتب','صلح','سلح']),('he',['כתב','צלח']),('syc',['ܟܬܒ'])]:
                with sqlite3.connect(folder/f'en-{code}.sqlite') as db:
                    db.executescript(SCHEMA)
                    for native in roots:
                        db.execute('INSERT INTO semRoot VALUES(?,?,?,?,?,?,?,?)',(identifier(code,native),code,' '.join(native),'','',native,'https://example.invalid/source',''))
            meta=build(folder,folder/'families.sqlite',notes=[])
            self.assertEqual(meta['families'],2);self.assertEqual(meta['triple'],1)
            with sqlite3.connect(folder/'families.sqlite') as db:
                self.assertEqual(db.execute("SELECT languages FROM family WHERE label='k-t-b'").fetchone()[0],'ar,he,syc')
                self.assertEqual(db.execute("SELECT count(*) FROM family WHERE basis<>'consonants'").fetchone()[0],0)
                self.assertEqual(db.execute("SELECT count(*) FROM member WHERE native='س ل ح'").fetchone()[0],0)
            first=(folder/'families.sqlite').read_bytes()
            build(folder,folder/'families.sqlite',notes=[])
            self.assertEqual(first,(folder/'families.sqlite').read_bytes())

    def test_reviewed_link_is_exact_and_does_not_capture_homographs(self):
        with sqlite3.connect(':memory:') as db:
            db.executescript(SCHEMA)
            for ident,word,gloss in [('dog','كَلْب','dog'),('rabies','كَلَب','rabies'),('wrong-sense','كَلْب','unrelated')]:
                db.execute('INSERT INTO semLexeme VALUES(?,?,?,?,?,?,?,?,?,?,?)',(ident,None,'ar',word,word,'',gloss,'noun','','https://example.invalid/source',''))
            notes=[dict(roots={'ar':'كلب'},summary='dog',sources=['https://example.invalid/root'],links=[dict(language='ar',word='كَلْب',pos='noun',gloss='dog')])]
            apply_reviewed_links(db,'ar',notes)
            linked=[r[0] for r in db.execute('SELECT id FROM semLexeme WHERE rootID IS NOT NULL')]
            self.assertEqual(linked,['dog'])

    def test_uncertain_association_can_be_removed_without_deleting_vocabulary(self):
        with sqlite3.connect(':memory:') as db:
            db.executescript(SCHEMA)
            root=identifier('ar','كلب')
            db.execute('INSERT INTO semLexeme VALUES(?,?,?,?,?,?,?,?,?,?,?)',('ant',root,'ar','كُعْلُبَة','','','An ant of the genus Atta.','noun','','source',''))
            note=dict(roots={'ar':'كلب'},excludedLinks=[dict(language='ar',word='كُعْلُبَة',pos='noun',gloss='An ant of the genus Atta.')],links=[])
            apply_reviewed_links(db,'ar',[note])
            self.assertEqual(db.execute('SELECT count(*) FROM semLexeme').fetchone()[0],1)
            self.assertIsNone(db.execute('SELECT rootID FROM semLexeme').fetchone()[0])

if __name__=='__main__':unittest.main()
