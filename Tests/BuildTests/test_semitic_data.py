import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import sys
import tarfile
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'Tools'))
from prepare_semitic_packs import roots,root_letters,key,build
from prepare_syriac_corpus import feature

class SemiticDataTests(unittest.TestCase):
    def test_roots_require_explicit_evidence_in_the_right_language(self):
        self.assertEqual(roots({'word':'كتب','pos':'verb'},'ar'),[])
        record={'word':'كتب','pos':'verb','etymology_templates':[{'name':'ar-rootbox','args':{'1':'ك ت ب'}}]}
        self.assertEqual(roots(record,'ar'),['كتب'])
        self.assertEqual(roots(record,'he'),[])
        self.assertIsNone(root_letters('katab','ar'))
        self.assertEqual(key('כָּתַבְתִּי'),'כתבתי')

    def test_text_fabric_sparse_ranges_and_implicit_nodes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'source.tar'
            data='@node\n@valueType=str\n\n2\tܟܬܒ\nܟܬܒܐ\n6-7\tܐܡܪ\n'.encode()
            with tarfile.open(path,'w') as archive:
                info=tarfile.TarInfo('corpus/tf/0.9/lex.tf');info.size=len(data);archive.addfile(info,io.BytesIO(data))
            with tarfile.open(path) as archive:result=feature(archive,'lex')
            self.assertEqual(result,{2:'ܟܬܒ',3:'ܟܬܒܐ',6:'ܐܡܪ',7:'ܐܡܪ'})

    def test_english_concepts_do_not_import_parenthetical_objects(self):
        record={'word':'كتب','lang_code':'ar','pos':'verb','head_templates':[{'name':'ar-verb','args':{'1':'I'}}],
                'etymology_templates':[{'name':'ar-rootbox','args':{'1':'ك ت ب'}}],
                'forms':[{'form':'كَتَبَ','tags':['canonical']},{'form':'invalid','tags':['error-unrecognized-form']}],
                'senses':[{'glosses':['to mark (letters, shapes), to write, to inscribe']}]}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'sample.jsonl';source.write_text(json.dumps(record)+'\n')
            counts=build(source,root,'ar',{'extractionDate':'fixture','url':'https://example.invalid/source','sha256':'fixture'})
            with sqlite3.connect(root/'en-ar.sqlite') as db:
                concepts={r[0] for r in db.execute('SELECT lemma FROM entry')}
                self.assertEqual(concepts,{'mark','write','inscribe'})
                self.assertEqual(db.execute('SELECT count(*) FROM semForm').fetchone()[0],1)
                self.assertEqual(db.execute("SELECT count(*) FROM semForm WHERE source='' OR status<>'attested'").fetchone()[0],0)
                self.assertEqual(counts['semRoot'],1)

if __name__=='__main__':unittest.main()
