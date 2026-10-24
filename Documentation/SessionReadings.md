# Vocabulary contrast and temporary readings — 2026-10-23

The requested behavior overrides the earlier requirement to archive generated readings. Readings now exist only in memory for the lifetime of the app process. Backgrounding retains them and releases inference resources; force-closing the app or iOS terminating its process clears them. Saved vocabulary, lists, preferences and review history remain persistent. New vocabulary saves retain the relevant example sentence, rather than the whole passage.

## Implemented

- Resolved English/target lemmas and rendered forms are checked for international lookalikes before replacement allocation. Case, diacritics, Cyrillic transliteration, common spelling differences and noun suffixes are normalized. Examples covered by regression tests include information/информация, rationality/рациональность, concept/концепция and German Information/Hunger.
- The English generation prompt names the enabled practice languages and receives noun hints verified against actual local packs. International terms may occur naturally but are not the focus of practice. Neither target-language translations nor earlier prose enter the model prompt.
- Each native inference attempt owns a fresh context and sampler. In-memory scenario planning avoids repeated base situations for the first 12 generations in a cycle and never repeats an entire situation/focus/perspective combination within the 576-combination pool. Duplicate and near-duplicate outputs are rejected using text, opening, phrase and content-word overlap, with the existing two-attempt retry limit.
- ReadingSession owns readings, reversible spans, Remix updates and novelty history. Migration v2 removes the old generatedText/replacement tables and their archive; it preserves vocabulary examples, decks, settings, SRS cards and review logs.

## Files

Added: Core/Languages/LexicalContrastPolicy.swift; Core/Generation/GenerationVocabularyPlanner.swift; Core/Generation/ReadingSession.swift; Core/Domain/VocabularyContext.swift; Tests/CoreTests/LexicalContrastTests.swift; Tests/CoreTests/ReadingSessionTests.swift; this document and Evidence/Session-and-contrast-validation.json.

Modified: App/AppEnvironment.swift; Core/Generation/TextGenerationService.swift; Core/Languages/ContextualReplacementEngine.swift; Core/Persistence/DatabaseManager.swift; Inference/LlamaCppService.swift; Features/Generate/GenerateView.swift; Features/Settings/SettingsView.swift; UIComponents/InteractivePassageView.swift; Tests/CoreTests/GenerationAndSpanTests.swift; Tests/CoreTests/PersistenceTests.swift; Tests/CoreTests/ReplacementEngineTests.swift; Tools/ModelSmoke/main.swift; README.md; Documentation/Architecture.md; Documentation/LanguagePackFormat.md; Documentation/Status.md.

## Executed validation

- Final offline build: 37 core Swift tests, 4 inference Swift tests and 7 build-tool tests passed. Simulator app compilation and actual app-bundle resource/checksum verification passed.
- Migration tests start from the v1 schema with a reading, replacement, saved word/example, deck membership, card due date, review history and settings. v2 removes only the reading tables and preserves the remaining data and foreign-key integrity.
- Actual Qwen inference on the Mac generated two Education passages using seeds 42/43, distinct scenarios 469/44 and novelty histories of 0/1. The final concise prompt produced 138 and 77 words, each after two bounded attempts. This is an execution check, not CEFR certification or physical-device performance measurement. Developer-only diagnostic output is in ignored .bootstrap/logs/session-generation-check.*; the app writes no reading archive.
- Simulator runtime: a 104-word passage appeared with mixed vocabulary; returning from the Home screen retained it; terminating/relaunching the process showed an empty reading session. The upgraded simulator database contained v1/v2 migration records and no generatedText/replacement tables. The final package was installed and launched on iPhone Duo / iOS 27.1.

## Limits and next checks

The lexicons have no reliable etymology field. The filter measures transparent word similarity, not proven native origins; some borrowings may escape and some useful cognates may be skipped. A later language pack can add reviewed provenance/learning-value annotations. Safety and sense checks still take precedence over replacement density.

Scenario and overlap checks reduce repetition but cannot prove semantic uniqueness. The small model still sometimes misses length/topic instructions, and the 77-word test output is below the preferred 90–150-word range despite passing the existing structural bounds. No model was switched, no network service was added, and no human linguistic-quality certification is claimed.

Physical iPhone 13 performance, fresh-install airplane-mode behavior and extended linguistic review were not repeated in this milestone. Next: review distinctive-word selection and same-topic variation on the physical phone; expand a reviewed evaluation set from any incorrect or transparent substitutions encountered. FSRS implementation remains outside this change.
