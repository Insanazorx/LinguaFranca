# Modular language packs and Latin Vocab

## Shipped languages

The app now bundles German, Russian, Arabic, Hebrew, Classical Syriac, Latin (`la`), Spanish (`es`) and French (`fr`). Adding a language does not enable it in an existing user's reading settings. All dictionaries are available regardless of the reading-language selection. Balanced retains the original generation/replacement pipeline. Aggressive retains the separate 2B model and complete selected-category coverage checks.

The three new June 2026 WikDict exports contain 25,424 Latin, 89,023 Spanish and 98,102 French senses. Pinned UniMorph revisions add 184,994 Latin, 840,143 Spanish and 191,080 French attested forms. Downloads happen only during development through `build.sh`; source URLs, byte counts, SHA-256 values, revisions and licenses are in `Dependencies.lock.json`.

`LanguageWritingProfile` describes the script, generation-language name and whether Apple's language detector supports the language. The same data drives generation prompts, repair grammar, target-script validation and vocabulary-writing practice. Latin does not claim support from Apple's language detector; Latin text receives script, completion and vocabulary-coverage checks. These checks cannot prove grammatical or semantic correctness. New languages still need a suitable model and, for richer grammatical behavior, a morphology adapter.

The new packs use indexed `lexicalForm` tables. Reverse dictionary lookup and writing-practice coverage use attested forms. Balanced may select unique recorded noun plurals and indicative present verb forms where its existing constraints permit them; ambiguous forms, unsupported agreement and tense/aspect mappings remain conservative. Aggressive translations remain model-generated and are not certified by a script check.

## Offline add-on format

A `.lfpack` is a folder, not executable code and not a downloaded runtime plug-in. Version 1 contains:

```
en-it.lfpack/
  addon.json
  en-it.json
  en-it.sqlite
  LICENSE.txt
  _dictionary/
    search.sqlite
    manifest.json
```

An optional `en-it.policy.json` may choose between already attested translations. `addon.json` declares `formatVersion: 1`, `metadataFile`, and each payload's `path`, `byteCount` and `sha256`. The language metadata retains schema version 1 and adds an optional `writingProfile`. Existing bundled manifests without this field remain compatible.

A future plain lexical pack can be built with `Tools/prepare_language_packs.py --source SOURCES --output PACKS --language it:Italian`. Supply the actual licensed `en-it.sqlite3` export. Record its immutable source/hash in the build lock to restore it through the build pipeline. Optional attested morphology is independent of the lexical importer.

Export an existing pack with:

```
python3 Tools/package_language_addon.py \
  --manifest Resources/LanguagePacks/en-it.json \
  --license Resources/CC-BY-SA-4.0.txt \
  --output build/LanguageAddons/en-it.lfpack
```

Include all applicable license texts in the supplied license document when the pack contains multiple sources. The exporter creates an independent search index containing only this language, copies the data and license, and computes the envelope hashes. It refuses to overwrite an existing export.

Open **Settings → Language packs → Add a language pack**, or the same action in Dictionary, and choose the `.lfpack` folder. Installation checks size/hash, safe relative paths, symlinks, metadata, lexical schema and SQLite integrity, and that the search index declares the same single language. The app validates a private staged copy before publishing it atomically into its own Application Support directory. No internet access is involved. Restart discovery also loads installed packs. Reading, dictionary lookup and study see the same combined registry. A bundled or already installed language cannot be replaced through this first version of the importer; pack updates/removal need a later explicit workflow. Saved vocabulary and review history remain independent of pack lifetime.

Only predefined script profiles are supported: Latin, Cyrillic, Arabic, Hebrew and Syriac. Supporting another script or a new specialist morphology system requires an explicit adapter change. The format does not promise universal language competence from the local model.

## English lookup across all languages

Dictionary defaults to **English → all languages**. An English lemma or expression is looked up exactly in every installed dictionary, with separate sections and independent result limits. Polysemous words retain each sense and definition. Missing equivalents are shown explicitly, with no fabricated LLM translation. **Browse dictionaries** retains target-word, inflected-form and transliteration search. Pagination over imported indexes merges bounded pages and uses language-scoped stable record identities.

## All passage vocabulary to a study list

Every generated or saved passage offers **Add words to a study list**. The user chooses an existing list or names a new list; all translated expressions are added together. English words that have no target-language equivalent are not converted into English-only cards. Repeated identical lexical identities are deduplicated, different meanings and languages remain distinct, and each card keeps its source/mixed sentence and any Semitic lexical reference. List creation, vocabulary, cards and memberships commit in one transaction. Existing FSRS cards, schedules and review logs are reused. Saving words does not implicitly archive the whole passage.

## Latin Vocab

Dictionary and Vocabulary link to **Latin Vocab**. The rebuilt catalog has **7,816 families, 19,328 distinct native headword strings and 52,976 dictionary sense/member records**. Any two of Latin, Spanish and French are sufficient. English is neither a member language nor an intermediary origin node, and matching English meanings or parts of speech are never required. Search uses native words only; each dictionary sense still provides its independent English explanation.

There are **3,514 recorded-origin groups** and **4,302 identical-spelling groups**. They are labelled separately. Identical spelling is not asserted to prove cognacy or equal meaning; false friends and historical homographs can appear. Pair filters include Latin–Spanish (2,935 groups), Latin–French (2,475) and Spanish–French (4,716). A three-language group contributes to more than one pair, so these totals overlap. Proper names and different senses/forms are not equivalent to distinct etymological roots.

The historical source is Gerard de Melo's **Etymological Wordnet 2013-02-08**, derived from Wiktionary and distributed under CC BY-SA 3.0. The pinned archive and original readme establish attribution/license. The builder follows only directed `etymology`/`etymological_origin_of` edges through bounded, cycle-safe paths (up to eight edges, first Latin origin). For each native pair it chooses the nearest recorded common ancestor to avoid redundant giant distant-root families. English nodes, generic related edges and derived-form edges are excluded. Exact identities retain accents/macrons. Accent-folded source matching requires uniqueness on both sides; ambiguous matches are skipped. Latin inflections can resolve through a unique attested UniMorph lemma. A separate exact native-spelling join covers words without shared recorded ancestry. No spelling-distance heuristic invents cognates.

These are word-level links, not sense-level etymological proof. Historical homographs and semantic changes cannot always be disambiguated from this old source without introducing assumptions; members therefore retain all attested dictionary senses and their individual source identities. Coverage is incomplete and single-headword based. Dictionary definitions retain their WikDict CC BY-SA 4.0 provenance; the historical edge data retains CC BY-SA 3.0.

## Validation on 27 October 2026

The source data and its checksums were restored from the local build cache without runtime downloads. The actual 2B model generated an English exercise mixing Latin, Spanish and French in one passage; all 16 selected structure expressions had mappings (25.99 seconds on the Mac host). This establishes orchestration and coverage only, not independent linguistic certification or iPhone speed. New-language physical-device generation, thermal and peak-memory measurements have not been performed. The existing bounded iPhone inference policy is retained.

## Dictionary from a study card

After flipping a card, tap its target word to open dictionary inspection. Source-linked words open their recorded lexical sense directly; model/manual words retain their saved meaning/example and offer possible dictionary senses instead of guessing one. Closing inspection returns to the same card and same face, without a review or scheduling change. Time spent in dictionary inspection is excluded from the card's review elapsed time.

## Two-card physical stack

Study renders the current card plus one closed backing card, with a slight angle, offset, edge and shadow. Moving the current card reveals the backing card, which rises toward the front during the swipe. After a successful review its color becomes the new front card's color. Only these card layers are rendered; the remainder of the selection does not create card faces or dictionary lookups. The backing card is hidden from accessibility and hit testing. A one-word selection shows a single card. Card dimensions remain 2:3, drag/flip/dictionary behavior and FSRS scheduling are retained.

## Word types and alphabetic browsing — 28 October 2026

Latin Vocab offers All words, Nouns, Verbs and Proper names. Selection is stored automatically in local preferences and reused at both Latin Vocab entry points. It filters both family previews and their individual dictionary senses. Native parts of speech come from the existing recorded dictionary metadata; homographs can legitimately have separate records in multiple types. No capitalization-based classifier or new English-meaning join is introduced.

A filtered family still needs the selected type in at least two languages, including both languages of a requested pair. Counts and native-word searches use only qualifying visible senses. Filtered row headings use an attested selected headword, preferring Latin then Spanish then French; historical ancestors remain labelled as origin information. Main results and member lists sort alphabetically with explicit case/diacritic folding, deterministic tie-breakers and stable pagination. This fixes capitalized names sorting before every lowercase word under POSIX collation.

Tests: 119 Core + 9 inference Swift tests passed; 23 Python build/data tests passed. New fixtures cover noun/proper-name homographs, mixed-type families that fail a selected pair, hidden-sense search exclusion, independent English gloss exclusion, filtered counts and case/diacritic-sensitive pagination boundaries. Native Mac displayed the new selector and counts; the final Mac/iPhone Release builds passed bundled checksums and signing. The latest iPhone Release installed and launched, and complete before/after library rows (vocabulary, lists/memberships, cards/reviews, saved readings and settings) match. No dictionary-source rebuild or user-library migration was needed. Physical manual category-switch interaction and sustained query profiling were not performed in this checkpoint; no inference behavior changed.

Files: Core/Dictionary/LatinVocabulary.swift; both Features/Dictionary/LatinVocabularyView.swift platform copies; Tests/CoreTests/LatinVocabularyFilterTests.swift; this guide and Status.md.
