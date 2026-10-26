import hashlib
import io
import json
from pathlib import Path
import sqlite3
import sys
import tarfile
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'Tools'))
from prepare_additional_language_forms import build,key

class AdditionalFormsTests(unittest.TestCase):
    def test_only_attested_known_lemmas_are_imported_with_mood_case_and_provenance(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            with sqlite3.connect(root/'en-es.sqlite') as db:
                db.execute('CREATE TABLE entry(translations TEXT)')
                db.executemany('INSERT INTO entry VALUES(?)',[(json.dumps(['casa']),),(json.dumps(['hablar']),)])
            (root/'en-es.json').write_text(json.dumps(dict(version='fixture',supportedFeatures=[],licenseMetadata={})))
            lines='casa\tcasas\tN;PL\nhablar\thablo\tV;IND;PRS;1;SG\nhablar\thable\tV;SBJV;PRS;1;SG\nhablar\thablado\tV;V.PTCP;PST;MASC;SG\nmissing\tmissing\tN;SG\n'
            with tarfile.open(root/'forms.tar.gz','w:gz') as archive:
                data=lines.encode();member=tarfile.TarInfo('fixture/spa');member.size=len(data);archive.addfile(member,io.BytesIO(data))
            spec=dict(languageCode='es',morphology=dict(filename='forms.tar.gz',iso='spa',url='https://example.invalid/test',revision='fixture'))
            self.assertEqual(build(root,root,spec),4)
            with sqlite3.connect(root/'en-es.sqlite') as db:
                self.assertEqual(db.execute("SELECT form,tense,person,number FROM lexicalForm WHERE surface='hablo'").fetchone(),('finite','present','1','singular'))
                self.assertEqual(db.execute("SELECT form FROM lexicalForm WHERE surface='hable'").fetchone(),('inflected',))
                self.assertEqual(db.execute("SELECT form FROM lexicalForm WHERE surface='hablado'").fetchone(),('participle',))
                self.assertEqual(db.execute("SELECT count(*) FROM lexicalForm WHERE source='' OR license<>'CC-BY-SA-3.0'").fetchone()[0],0)
            manifest=json.loads((root/'en-es.json').read_text())
            self.assertEqual(manifest['licenseMetadata']['databaseSHA256'],hashlib.sha256((root/'en-es.sqlite').read_bytes()).hexdigest())
    def test_keys_fold_macrons_and_accents_without_changing_original_forms(self):
        self.assertEqual(key('LĪBER'),'liber')
        self.assertEqual(key('niños'),'ninos')
