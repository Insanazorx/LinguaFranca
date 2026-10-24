# Lexical resources and provenance

## Bilingual records

Source: https://www.wikdict.com/page/download, June 2026 SQLite exports en-de.sqlite3 / en-ru.sqlite3. Attribution: WikDict by Karl Bartel; Wiktionary contributors via DBnary. Data license: CC BY-SA 4.0. Each manifest/entry records source URLs and exact hashes.

Tools/prepare_language_packs.py normalizes NFC, filters malformed/non-good records, deduplicates and indexes POS, senses, glosses and translation alternatives. Derived data retains CC BY-SA 4.0. Selection policies only choose translations present in each source sense. Absent upstream examples are not invented.

## German forms

Source: Gregor Weichbrodt / german-nouns / WiktionaryDE contributors, https://github.com/gambolputty/german-nouns. Pinned PyPI 1.2.5. License CC BY-SA 4.0. Wheel SHA256: 0f113c59ea331aae750bc03c7b6c7217bae975c6677b4df8d8932093093f509f.

Only attested nominative plural forms are imported. Conflicting forms such as Banken/Bänke require disambiguation and are skipped.

## Russian forms

Source: OpenCorpora, https://opencorpora.org/?page=downloads, distributed through pymorphy3-dicts-ru 2.4.417150.4580142. Data license CC BY-SA 3.0, retained separately from bilingual CC BY-SA 4.0 records. Wheel SHA256: 718bac64c73c10c16073a199402657283d9b64c04188b694f6d3e9b0d85440f4.

Build-only MIT tools pymorphy3 2.0.6 and dawg2-python 0.9.0 read the fixed dictionary. Unknown-word predictions are excluded. All attested nominative plurals are retained; ambiguous alternatives such as листы/листья are skipped. Python is not included in the iOS app. The reader code's MIT license does not replace the dictionary data license.

## English analysis

Source: NLTK averaged_perceptron_tagger_eng. Model metadata explicitly declares MIT: https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/taggers/averaged_perceptron_tagger_eng.xml. Attribution: Matthew Honnibal (2013), Long Duong and NLTK Project (2015).

Archive SHA256: 6025f530624335c67d6547d44757b357b4e79bae030a0383e9887a92c1718f0b. JSON weights are bundled unchanged under Resources/LanguagePacks/_english, with full MIT text and individual hashes. Prediction is native Swift. Reference fixtures run the original unmodified NLTK3.9.2 classes against those weights.

Full CC BY-SA3.0/4.0 and MIT texts, attribution and modification notices ship with the app. Derived SQLite files and preparation scripts are ordinary project files; no extra data restrictions or DRM are applied.

## Practice-form expansion — 2026-10-23

German verbs and predicate adjectives now also use the UniMorph German paradigms, extracted from English Wiktionary, under CC BY-SA 3.0. Upstream license and description: https://github.com/unimorph/deu . Pinned commit: d226d2112d3490d8f04ece10d4538123d4297a39. Source archive SHA-256: ece48b98ba3b5dc43d8cba110d71b4427cab03801ffc650718b33975fa82cf97. The existing bundled CC-BY-SA-3.0.txt supplies the license text. Attribution is also in THIRD-PARTY-NOTICES.txt.

Russian verb and short-adjective forms come from the already pinned OpenCorpora/pymorphy3 dictionary under CC BY-SA 3.0. The reader accepts only known dictionary lemmas and attested lexemes. Tools/prepare_practice_forms.py filters these sources into indexed single-token practiceForm rows; it does not generate translations. Multiword/separable forms and unsupported grammatical features are skipped. Final packaged counts: German 54,467 verb / 6,793 adjective rows; Russian 54,572 verb / 17,074 adjective rows. Manifests are version lf3 with updated database hashes. Source archives remain build-only; there are no runtime downloads.
