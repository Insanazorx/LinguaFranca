# Language pack format

Each top-level en-<code>.json manifest declares language code/name, schema version, pack version, SQLite name, supported features, attribution/licenses and source/derived database hashes. en-<code>.policy.json optionally chooses common translations already present in a sense. Policies cannot invent a translation.

SQLite entry records contain lemma, POS, stable sense ID, source gloss, translation alternatives, upstream score and provenance. An index covers lemma/POS. nounForm records contain normalized target lemma, number, attested surface, gender, source and license, indexed by lemma/number. caseForm adds grammaticalCase with an index on lemma/number/case, for attested German/Russian noun phrases. Ambiguous or missing forms are skipped. German article paradigms are applied only with a unique gender. Russian spatial second-locative choices require lexical support.

_english contains the shared MIT English POS JSON model and its manifest/license. These files are not target-language manifests. Registry discovery excludes policies/coverage metadata and is independent of the number of languages.

Rebuild lexical records with Tools/prepare_language_packs.py, then augment noun forms with Tools/prepare_morphology.py. Recompute manifest hashes after changing SQLite data. Keep derived-data licenses and full notices. Session readings retain surfaces/sense IDs/pack versions in memory. Saved vocabulary and its example sentence remain independent of pack changes. The lookalike filter operates on existing dictionary pairs; no etymology field or invented translation is added.

practiceForm adds indexed lemma/POS/form/tense/person/number/gender/surface/source/license records. German UniMorph and Russian OpenCorpora provide attested forms. Missing/ambiguous rows return no replacement. German predicate adjectives and finite/nonfinite verbs are supported where safe; Russian finite present, infinitive, converb, gender/number-marked short predicate adjectives and explicitly habitual imperfective past are supported. General attributive agreement, progressive-phrase conversion, unknown Russian past gender, arbitrary aspect and separable-verb syntax remain unsupported.

lf4 also exposes bounded form sets for vocabulary-writing coverage checks. These allow valid inflections of saved words in monolingual generated texts; they do not weaken contextual substitution or case validation.

## Modular add-ons and additional languages (27 October 2026)

See [ModularLanguages.md](ModularLanguages.md) for the `.lfpack` envelope, data-only script profiles, offline installation/export, lexicalForm schema, English lookup across all installed languages, passage vocabulary import and the separate source-recorded Latin Vocab catalog. Existing schema-1 packs, user libraries and FSRS histories remain compatible.
