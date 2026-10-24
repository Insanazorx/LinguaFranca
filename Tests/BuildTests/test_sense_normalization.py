import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('language_packs',Path(__file__).resolve().parents[2]/'Tools/prepare_language_packs.py')
packs = importlib.util.module_from_spec(spec); spec.loader.exec_module(packs)

class SenseNormalizationTests(unittest.TestCase):
    def test_explicit_verbal_sense_is_not_lost_under_noun_uri(self):
        self.assertEqual(packs.sense_part_of_speech('work','noun','intransitive: to do a specific task'),'verb')
        self.assertEqual(packs.sense_part_of_speech('work','noun','labour, employment, occupation, job'),'noun')

    def test_as_is_classified_by_its_documented_sense(self):
        self.assertEqual(packs.sense_part_of_speech('as','adverb','In the role of'),'preposition')
        self.assertEqual(packs.sense_part_of_speech('as','adverb','at the same time that'),'conjunction')
        self.assertEqual(packs.sense_part_of_speech('as','adverb','Roman coin'),'noun')
