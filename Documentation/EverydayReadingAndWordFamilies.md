# Everyday reading, word families and vocabulary browser

## Implemented

- Rebuilt the bundled Latin Vocab schema/data builder and both native UIs. Any native pair qualifies; no English lemma/POS join or English intermediary nodes. Pair filtering, native search, separate relationship badges, independent dictionary senses, historical paths and dictionary saving are retained. The catalog is generated reproducibly by build.sh from the pinned, verified cache/source archive.
- Added Nichijou alongside B2/C1 without changing their stored values or old readings. It targets everyday English and practical scenarios, common/intermediate vocabulary, contractions and useful expressions. It is a register, not a new CEFR level or a Japanese target language. Balanced vocabulary hints include practical everyday concepts that still require real local dictionary matches.
- Reworked dialogue/theatre/poem prompts and grammars: short or longer replies, contractions, numbers and two sentences per reply, alternating speakers, theatre stage direction, preserved verse lines. Aggressive applies the same format grammar inside its JSON English field with escaped line breaks. Its English validation/novelty checks now participate in the existing bounded two-attempt policy. Embedded speaker changes and missing stage directions are rejected. Every word remains model-generated.
- Moved generation level, topic, languages/frequencies, writing genre, replacement mode and category assignments above the reading. Changes update immediately and queue serialized local writes. Refresh does not overwrite pending edits; model release/normal app quit waits for pending preference writes. There is no Save preferences action. Legacy settings decode with the new topic default Random.
- Replaced the vocabulary landing page with list/language filters, search, alphabetic rows, green selection, a word-detail panel, dictionary/edit/practice actions and multiple-word selection. Compact iPhone navigation pushes detail and returns to the same browser. List management, removing membership versus deleting vocabulary, forgotten-word study, FSRS histories, and per-language whole-list generation remain available. No user-library migration was added.

## Main files

Core/Dictionary/LatinVocabulary.swift, Core/Domain/Models.swift, Core/Domain/ReadingOptions.swift, Core/Generation/TextGenerationService.swift, Core/Generation/GenerationVocabularyPlanner.swift, Inference/LlamaCppService.swift, Tools/prepare_latin_vocabulary.py, Tools/verify_app_bundle.py, Tools/ModelSmoke/FormatChecks.swift; both platform AppEnvironment, GenerateView, SettingsView, VocabularyView, LatinVocabularyView, StudyWordDictionaryView, and new GenerationOptionsView.

## Validation — 28 October 2026

- 116 Core tests and 9 inference tests passed. New cases cover independent native word meanings, two-language families, English exclusion, evidence labels, source paths, pair filtering, persisted Nichijou/topic settings, flexible short dialogue, theatre directions and embedded speaker rejection. Existing persistence, FSRS, dictionary, replacement and memory-policy tests passed.
- 23 Python build/data tests passed. Native-origin traversal is bounded/cycle-safe; accent identities, independent English glosses, separate exact spelling and excluded English/related/derived-form edges are checked.
- Actual Qwen3.5-0.8B Balanced and Qwen3.5-2B Aggressive generated dialogue, theatre and poetry on the Mac host. The final Aggressive examples had 6/6, 4/4 and 14/14 structure occurrences mapped. This proves format/orchestration/coverage, not semantic correctness of every translation, CEFR certification or physical iPhone performance.
- Native Mac UI: two-panel browser, word selection, examples, green theme and detail actions checked. Native iOS simulator UI: compact list-to-detail/back, dictionary inspection/back, individual multi-selection and starting/ending selected-card practice checked. Latin Vocab opens with the new catalog count. Nichijou/Dialogue choices were verified in the isolated test database without a Save action.
- Signed Mac Release, signed iPhone Release and iOS simulator builds include all eight dictionaries, both existing models, optional speech assets and the new catalog; bundle checksums verified. Production data is separate from test libraries. No network inference or runtime download was introduced. The installed Mac application was updated and reopened with its existing B2/Russian/Essay/Aggressive preferences and one saved reading visible. At the initial implementation checkpoint the new iPhone Release was built/signature-verified but not yet installed; see the subsequent physical-device session below.

## Limits and checks not performed

The supplied Japanese reference screenshot was unavailable at its path; the list layout follows the user's described pane interaction and the app's green native theme. The initial checkpoint did not include physical-device inference. The subsequent session below measured two real generations; sustained thermal/performance testing remains open. The available iOS 27.1 simulator runtime does not support an iPhone 13 device type; compact UI tests used the existing iPhone Duo simulator. The simulator does not establish phone inference memory/performance. The bounded iPhone inference policy and model lifecycle are unchanged.

Small local models still produce occasional awkward or implausible phrases, imperfect verse and translation/grammar errors. Format validation does not certify literary quality or every word sense. The dictionaries and 2013 etymology extraction are incomplete; identical spellings can be false friends. Unsaved generated readings remain process-memory only; explicitly saved readings and study history keep their existing behavior.

## Evidence

Local build/test reports are under .bootstrap/logs/: nichijou-library-mac-release.log, nichijou-library-iphone-release.log, nichijou-library-ios-final.log, swift-tests.log, build-tool-tests.log, nichijou-balanced-formats-final.json and nichijou-aggressive-formats-final.json. They are generated/ignored artifacts, not fabricated fixtures or production user readings.

## Subsequent physical iPhone session — 28 October 2026

The user connected their physical iPhone 13 (iOS 27.0.1). The signed Release replaced the existing app and launched. A safety copy and SQLite quick checks preceded installation. Full rows of vocabularyItem (164), studyDeck (2), deckVocabulary, srsCard (164) and reviewLog (58) match the before-update copy, and all nine original savedReading rows remain identical. The user explicitly saved both test readings, yielding 11 saved readings. Raw library copies remain local in /private/tmp; the repository includes only the sanitized report at Evidence/iPhone13-nichijou-validation.json.

| Real phone request | Model | Whitespace words | Speaker turns | Generation duration | Selected replacements |
|---|---|---:|---:|---:|---|
| Balanced · Nichijou · Dialogue · Education | 0.8B | 82 | 6 | 10.687 s | 11 substitutions under Balanced frequency |
| Aggressive · Nichijou · Dialogue · Society · Russian content words | 2B | 68 | 6 | 75.303 s | 16/16 detected occurrences, 16 repairs |

The user operated the physical phone because Device Hub did not supply interactive touches. Live device screen capture, debugger console attachment and heavy system profiling were closed during inference. Both actions completed and were saved; no termination was reported. The 2B raw stage recorded 16 GPU layers, micro-batch 16 and an allocated 2304-token context under the retained bounded-memory policy. Its raw sampled process footprint was 260,721,776 bytes; Balanced's was 212,945,336 bytes. These are sampled process counters, not continuously measured resident/system-wide lifetime peaks; later Aggressive repair calls are not included in the retained peak field.

The user confirmed word-list detail/dictionary navigation and Latin Vocab Spanish–French group browsing both work. A brief physical-screen check also showed the Juan/Jean group details. The real phone's dark theme exposed low-contrast green text; App/LinguaFrancaApp.swift now uses an adaptive UIColor matching the Mac green palette. The corrected signed iPhone Release was rebuilt, bundle/signature-verified, installed and reopened after both readings had been saved. The brighter dark-theme navigation accent was observed. No additional algorithm tests were needed for this color-only change.

This is functionality and one run per inference mode, not a repeated-run thermal/battery benchmark, a fresh-install airplane-mode test, or certification of meaning. A concrete semantic error remains: the 2B result maps serving tray to миска (food bowl), while the bundled dictionary offers поднос and related serving-tray equivalents. The result therefore passes detected-slot coverage while failing this lexical meaning. Source Sense validation is a remaining quality follow-up. The user's final settings persist Aggressive + Nichijou + Dialogue with Russian and content/actions enabled; the recorded Aggressive measurement specifically exercised content-only, before their later actions selection.
