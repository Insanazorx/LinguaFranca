# Language pack format

Each top-level en-<code>.json manifest declares language code/name, schema version, pack version, SQLite name, supported features, attribution/licenses and source/derived database hashes. en-<code>.policy.json optionally chooses common translations already present in a sense. Policies cannot invent a translation.

SQLite entry records contain lemma, POS, stable sense ID, source gloss, translation alternatives, upstream score and provenance. An index covers lemma/POS. nounForm records contain normalized target lemma, number, attested surface, gender, source and license, indexed by lemma/number. Only unique nominative plural forms are currently used; no case/verb/adjective rules are fabricated.

_english contains the shared MIT English POS JSON model and its manifest/license. These files are not target-language manifests. Registry discovery excludes policies/coverage metadata and is independent of the number of languages.

Rebuild lexical records with Tools/prepare_language_packs.py, then augment noun forms with Tools/prepare_morphology.py. Recompute manifest hashes after changing SQLite data. Keep derived-data licenses and full notices. Generated readings store surfaces/sense IDs/pack versions so originals and earlier readings survive pack changes.
