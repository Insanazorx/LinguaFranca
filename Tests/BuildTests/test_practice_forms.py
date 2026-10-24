import importlib.util
from pathlib import Path
import sqlite3
import unittest

spec=importlib.util.spec_from_file_location('practice_forms',Path(__file__).resolve().parents[2]/'Tools/prepare_practice_forms.py')
forms=importlib.util.module_from_spec(spec);spec.loader.exec_module(forms)

class PracticeFormsTests(unittest.TestCase):
    def test_stress_is_removed_without_destroying_yo(self):
        self.assertEqual(forms.key('Улыба́ться'),'улыбаться')
        self.assertEqual(forms.key('Ёлка'),'ёлка')

    def test_multiword_and_separable_forms_are_not_packaged_as_single_tokens(self):
        db=sqlite3.connect(':memory:')
        db.execute('CREATE TABLE practiceForm(lemma,pos,form,tense,person,number,gender,surface,source,license)')
        forms.insert(db,'gehen','verb','finite','geht','fixture')
        forms.insert(db,'ausgehen','verb','finite','geht aus','fixture')
        self.assertEqual(db.execute('SELECT surface FROM practiceForm').fetchall(),[('geht',)])
