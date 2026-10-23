
# AGENTS.md — LinguaFranca

## 1. Project Identity

Project name: LinguaFranca

Platform: Native iOS application

Primary test device: iPhone 13 (A15 Bionic, 4 GB RAM)

Implementation language: Swift 6

UI framework: SwiftUI

Architecture: Modular, protocol-oriented Swift with clear separation between UI, inference, language processing, and persistence.

Primary development goal:

Build a fully offline language-learning application that generates original B2–C1 English texts using a small on-device language model, then replaces selected English words or phrases with contextually appropriate translations from one or multiple user-selected target languages.

The replacement technique is inspired by the functionality of Toucan, while the offline-first philosophy and vocabulary study experience are inspired by Japanese by Renzo Inc.

These are functional references, not codebases or UI designs to copy.

LinguaFranca must have its own implementation, architecture, interface, assets, and identity.

This project is intended to become a real, usable iOS application, not merely a prototype.

## 2. Non-Negotiable Product Requirements

1. The application must work entirely offline, including on its first launch.
2. No cloud inference, server, API key, account, or internet connection may be required.
3. The language model must execute locally on the iPhone.
4. The model must generate original English passages targeting CEFR B2 or C1.
5. A separate translation/replacement engine must process the generated English text.
6. The translation engine must perform context-sensitive lexical substitution, not literal word-by-word translation.
7. The initial target languages are German (`de`) and Russian (`ru`).
8. Multiple target languages must operate simultaneously inside one English passage.
9. Users must be able to tap any replaced word or phrase to reveal its original English expression.
10. Users must be able to save vocabulary directly from generated passages.
11. Users must be able to create, name, edit, and delete vocabulary study lists.
12. Saved vocabulary must be reviewable through a proper spaced repetition system (SRS).
13. Future target languages must be implementable by adding language packs and, when necessary, language-specific morphology adapters.
14. All vocabulary, decks, reviews, settings, and generated texts must be stored locally.
15. The application must be memory-conscious, responsive, and stable on iPhone 13.
16. No external text-reading/import feature is required. Generated passages are the only reading content for the initial product.

Do not introduce networking, subscriptions, authentication, cloud synchronization, or unrelated features.

## 3. Technology Decisions

Use the following default stack:

| Component | Technology |
|---|---|
| Application UI | SwiftUI |
| Language | Swift 6 |
| Concurrency | Swift Concurrency / actors |
| Local text generation | llama.cpp |
| Inference acceleration | Metal where supported |
| Model representation | GGUF |
| Initial LLM | Qwen3-1.7B |
| Quantization | Q4_K_M |
| Persistent database | SQLite |
| Database access | GRDB.swift |
| English linguistic processing | Apple NaturalLanguage + custom processing |
| Contextual substitutions | Custom LinguaFranca engine |
| Language dictionaries | Versioned local language packs |
| Spaced repetition | FSRS 6-compatible scheduler |
| Unit tests | Swift Testing / XCTest |
| Performance testing | XCTest metrics and Instruments |

Prefer native Apple frameworks whenever possible.

Do not introduce a large third-party dependency for functionality that can be implemented reliably with Foundation, SwiftUI, or NaturalLanguage.

Pin third-party dependency revisions for reproducible builds.

## 4. Local Language Model

### 4.1 Initial Model Selection

Start with:

- Model: Qwen3-1.7B (post-trained instruction model)
- Format: GGUF
- Quantization: Q4_K_M
- Runtime: llama.cpp
- Execution: Fully local
- Thinking mode: Disabled
- Network dependency: None

The model should generate English passages, not translate them.

Do not use a large language model to perform the complete Toucan-style replacement process.

Generation and lexical substitution must remain independent subsystems.

Source model:

https://huggingface.co/Qwen/Qwen3-1.7B

Possible quantized distribution:

https://huggingface.co/bartowski/Qwen_Qwen3-1.7B-GGUF

Before packaging the weights:

- Verify the exact model and GGUF revision.
- Verify the SHA-256 checksum.
- Record the upstream license and attribution.
- Confirm runtime compatibility.
- Confirm physical-device memory usage.
- Never assume GGUF file size equals runtime memory consumption.

### 4.2 Alternative Model Benchmark

Benchmark Qwen3.5-0.8B as a possible faster replacement if its GGUF variant is supported by the chosen iOS runtime.

Compare:

- English grammatical quality
- B2/C1 vocabulary range
- Coherence
- Prompt adherence
- Repetition
- Time to first token
- Total generation latency
- Memory consumption
- Thermal behavior

Do not select a smaller model merely because it generates faster if passage quality becomes unacceptable.

Bundle only the selected production model.

Do not silently download or switch models after installation.

### 4.3 Initial Inference Configuration

Use the following as starting values, not unquestionable final settings:

- Context window: 2048 tokens
- Maximum context if justified by testing: 4096 tokens
- Maximum generated tokens: 256–320
- Temperature: 0.7
- Top-p: 0.9
- Repetition penalty: approximately 1.05
- KV cache: smallest validated safe configuration
- Batch size: benchmark 32 and 64
- Threads: determined by physical-device profiling
- GPU offload: use supported Metal acceleration

Avoid allocating enormous KV caches merely because the original model advertises a much larger context window.

The application only needs short-form generation.

Prefer predictable memory consumption over theoretical maximum context length.

### 4.4 Generation Interface

Create this protocol:

`TextGenerationService`

Required functionality:

- `loadModel()`
- `generate(request:)`
- `cancelGeneration()`
- `unloadModel()`

Define a `GenerationRequest` containing:

- topic
- CEFR level
- approximate word count
- random seed
- optional style
- generation configuration

Define a `GenerationResult` containing:

- generated English text
- generation duration
- model identifier
- seed
- token count
- generation metadata

Use an actor or equivalent safe serialization mechanism so multiple model generations cannot compete for the same inference context.

Do not execute blocking inference on the main thread.

Support cancellation and properly release native resources.

### 4.5 Generation Behavior

The generated texts should:

- Be written in natural English.
- Target B2 or C1 according to the selected level.
- Usually contain 90–150 words.
- Be grammatically coherent.
- Have meaningful sentence transitions.
- Avoid repetitive structures.
- Cover diverse subjects.
- Contain vocabulary useful for language learning.

Example topics:

- Daily life
- Work and careers
- Technology
- Science
- Psychology
- Society
- Travel
- Literature
- Education
- Culture

Random selection should use local topic and style pools.

The user must also be able to select a topic manually.

The generated text must be clean prose without AI explanations, system messages, Markdown wrappers, or internal reasoning tokens.

Implement output validation and a bounded retry policy.

Generation should never result in an infinite retry loop.

Example generation prompt:

"Write an original, coherent English passage of approximately 110 words about everyday life. Target CEFR C1 vocabulary and sentence complexity while maintaining natural, readable English. Use varied vocabulary and logical transitions. Output only the passage. Do not provide a title or explanation. Do not translate any words."

Parameterize this prompt rather than hardcoding a single topic or level.

## 5. LinguaFranca Replacement Engine

This is the most important custom subsystem.

Name it:

`ContextualReplacementEngine`

It must be independently usable and independently testable without SwiftUI or the LLM.

### 5.1 Core Principle

The engine accepts an original English passage and produces a mixed-language reading representation.

Example original:

"The manager reached a decision after the meeting."

Possible German/Russian hybrid:

"The manager reached a решение after the Besprechung."

Mappings:

- decision → решение (Russian)
- meeting → Besprechung (German)

When the user taps `решение`, the interface must reveal `decision`.

When the user taps `Besprechung`, the interface must reveal `meeting`.

The English original must remain intact internally.

Never perform substitution by destructively overwriting the only copy of the source text.

### 5.2 Processing Pipeline

Implement the following pipeline:

1. Input original English passage.
2. Normalize text safely without losing original offsets.
3. Split text into sentences.
4. Tokenize each sentence.
5. Identify grammatical categories.
6. Lemmatize English words where supported.
7. Detect multiword expressions.
8. Identify candidate words suitable for replacement.
9. Detect relevant context and possible meanings.
10. Query local lexicon entries for each selected target language.
11. Rank candidate senses and translations.
12. Validate grammatical and contextual compatibility.
13. Choose replacement spans without overlap.
14. Apply user-selected replacement density and language distribution.
15. Construct a reversible mixed-language representation.
16. Return rendering metadata.

Translation lookup must use the original English source and its context.

Never translate an already substituted German or Russian word into another language.

### 5.3 Word Sense Disambiguation

A source word may have multiple meanings.

Example:

"She deposited money at the bank."

Here, `bank` means a financial institution.

"The children played near the river bank."

Here, `bank` means the side of a river.

The engine must distinguish these senses whenever sufficient information is available.

Potential techniques:

- Part-of-speech constraints
- Lexical sense identifiers
- Context keyword matching
- Nearby dependency patterns
- Multiword expression matching
- Curated example sentences
- Deterministic scoring
- Optional lightweight local semantic classification

Use confidence scores internally.

If a translation is ambiguous or cannot be verified, leave the word in English.

An untranslated word is preferable to an incorrect translation.

Do not assume that Apple's NaturalLanguage framework supplies complete Russian and German morphology or word-sense disambiguation.

Implement and test any unsupported functionality explicitly.

### 5.4 Morphological Awareness

Translations must be sensitive to:

- Part of speech
- Grammatical number
- Verb tense and aspect
- Noun and adjective forms
- Case, where relevant
- Gender, where relevant
- Idiomatic meaning
- Multiword expressions

German examples:

- gehen
- ging
- gegangen

Russian examples:

- делать
- сделал
- делаю
- делал

Do not blindly substitute dictionary citation forms where an inflected form is required.

However, German and Russian grammar cannot always be embedded naturally inside an English sentence.

Do not pretend that inflection alone solves the structural incompatibility between languages.

Prioritize standalone nouns, suitable adjectives, adverbs, established expressions, and safe substitutions.

Handle verbs and grammatically dependent phrases only when the result is defensible.

When a replacement would be misleading, unnatural, or grammatically incompatible, skip it.

### 5.5 Replacement Density

Provide a user-adjustable replacement-density setting.

Initial settings:

- Low: approximately 10%
- Medium: approximately 20%
- High: approximately 30%

These percentages are targets, not permission to generate incorrect substitutions.

Prefer approximately 25–35% of source word tokens in High mode where vocabulary coverage and grammar allow it.

Never force translation of articles, auxiliaries, prepositions, or other grammatical elements simply to achieve a numeric target.

Track actual replacement density and make it available for diagnostics.

### 5.6 Simultaneous Target Languages

The user may enable German and Russian at the same time.

Each selected language must have an adjustable share.

Examples:

- German 100%, Russian 0%
- German 50%, Russian 50%
- German 30%, Russian 70%

The distribution applies to the chosen replacement candidates, not to every word in the passage.

Future languages must participate in the same allocation process.

Implement a generic weighted language selector.

Requirements:

- No overlapping replacements.
- No chaining translations through another target language.
- No substitution of words previously substituted.
- Avoid excessive consecutive replacements.
- Prefer broad distribution across sentences.
- Reproducible output when using an identical random seed.
- Rebalance when a language lacks a safe translation candidate.

The engine must not assume exactly two languages.

### 5.7 Replacement Data Model

Create a model similar to:

`ReplacementSpan`

Fields:

- id
- sourceTextID
- originalUTF16Range
- renderedUTF16Range
- originalSurface
- originalLemma
- originalPartOfSpeech
- sourceSenseID
- targetLanguageCode
- targetLemma
- targetSurface
- translationConfidence
- languagePackVersion

Handle Unicode, Cyrillic, German diacritics, punctuation, and emoji safely.

Use consistent offsets between Foundation, NaturalLanguage, and the final text renderer.

Never assume Swift String indices are equivalent to UTF-16 offsets.

Prefer a token/span-based render model over repeated mutation of raw text.

### 5.8 Lexical Data Requirements

The replacement engine must use actual locally available lexical resources.

Do not simulate dictionary intelligence with a tiny collection of hardcoded examples.

Build an offline data preparation pipeline that can import, validate, normalize, deduplicate, and package appropriately licensed English–German and English–Russian lexical resources.

Target vocabulary coverage must include useful B2–C1 vocabulary and common contextual meanings.

Support:

- English lemma
- Target lemma
- Part of speech
- Sense identifier
- Contextual usage examples
- Inflected forms where available
- Morphological tags
- Multiword expressions
- Frequency or difficulty metadata
- Lexical source and license provenance

Do not redistribute dictionary datasets without checking their licenses.

Do not invent translations merely to meet vocabulary-count targets.

Maintain separate coverage metrics for German and Russian.

## 6. Extensible Language Pack Architecture

Do not hardcode German and Russian into the replacement engine.

Define a generic interface:

`LanguagePack`

Required capabilities:

- `metadata`
- `lookup(englishLemma:)`
- `lookupSense(...)`
- `inflect(...)`
- `validateReplacement(...)`
- `supportsPartOfSpeech(...)`

Use a manifest with fields similar to:

- id
- languageCode
- displayName
- version
- schemaVersion
- lexiconDatabaseName
- supportedFeatures
- licenseMetadata

Create initial implementations:

- `GermanLanguagePack`
- `RussianLanguagePack`

Use language-specific adapters where necessary:

- `GermanMorphologyAdapter`
- `RussianMorphologyAdapter`

Core replacement logic must not depend directly on either concrete implementation.

Future languages such as French, Spanish, Japanese, and Chinese should be addable without rewriting the engine.

A new language may require additional morphology or tokenization code; a data file alone is not guaranteed to be sufficient.

For the initial release, package German and Russian inside the app bundle.

Do not require language-pack downloads.

## 7. Local Database

Use SQLite through GRDB.swift.

Configure an appropriate database connection pool or queue.

Use migrations, indexed queries, prepared statements, and transactions.

Do not load entire dictionaries into Swift arrays at launch.

Use indexed SQLite queries and small memory-aware caches.

Suggested entities:

### GeneratedText

- id
- originalEnglish
- topic
- cefrLevel
- generatedAt
- modelID
- seed
- generationMetadata

### Replacement

- id
- generatedTextID
- sourceStart
- sourceLength
- renderedStart
- renderedLength
- originalExpression
- translatedExpression
- targetLanguage
- lexicalSenseID
- packVersion

### VocabularyItem

- id
- englishLemma
- targetLanguage
- targetLemma
- targetSurface
- senseID
- partOfSpeech
- exampleEnglish
- exampleMixed
- createdAt

### StudyDeck

- id
- name
- createdAt
- updatedAt

### DeckVocabulary

- deckID
- vocabularyItemID

### SRSCard

- id
- vocabularyItemID
- direction
- state
- dueAt
- stability
- difficulty
- repetitions
- lapses
- lastReviewedAt
- schedulerVersion

### ReviewLog

- id
- cardID
- rating
- reviewedAt
- elapsedTime
- scheduledInterval
- priorState
- resultingState

### Settings

- enabledLanguages
- languageWeights
- replacementDensity
- generationLevel
- defaultWordCount
- preferredTopics
- dailyReviewTarget
- desiredRetention

Create the necessary indexes and foreign keys.

Persist original generated text and replacement metadata so previously generated passages can be displayed consistently.

Define sensible behavior when language packs are upgraded.

Do not erase user SRS histories during migrations.

Use SQLite FTS5 for vocabulary search if it provides a clear benefit.

## 8. Spaced Repetition System

Implement a dedicated Study section inspired by the functionality of mature Japanese vocabulary-learning applications.

Do not copy their UI assets or source code.

Use an FSRS 6-compatible scheduling engine.

Prefer a validated implementation or a carefully tested Swift port of the reference algorithm.

Do not substitute an arbitrary interval formula and call it FSRS.

Preserve review history and scheduler-version metadata.

The scheduling implementation must pass reference test vectors.

### 8.1 Vocabulary Collection

Users must be able to:

- Tap a replaced word.
- Reveal the original English word or phrase.
- View its target-language equivalent.
- View the language.
- View a contextual example.
- Add the word to an existing deck.
- Create a new deck.
- Manually add vocabulary.
- Edit or remove saved vocabulary.
- Search their collected vocabulary.

Prevent unintended duplicates within a deck.

Do not merge distinct meanings simply because they share the same spelling.

### 8.2 Study Workflow

Implement flashcard review.

Card front examples:

`решение`

or

`Besprechung`

Card back:

- English equivalent
- Target language
- Original example sentence
- Relevant grammatical information

Provide four review ratings:

- Again
- Hard
- Good
- Easy

A review rating must update:

- Card state
- Due date
- Stability
- Difficulty
- Review history

Support:

- Due cards
- New cards
- Daily review targets
- Deck selection
- Learning progress
- Review counts
- Basic retention statistics

SRS scheduling must be entirely local and deterministic given its inputs.

Do not require a login or online account.

## 9. User Interface

Use clean, native SwiftUI.

Design for iPhone 13 first.

Primary navigation:

1. Generate
2. Study
3. Vocabulary
4. Settings

### 9.1 Generate Screen

Provide:

- CEFR level selector: B2 or C1
- Topic selector: Random or specific topic
- Word-count preference
- Language selection
- Per-language replacement weights
- Replacement density control
- Generate button
- Loading and cancellation state
- Mixed-language passage display

Generation sequence:

1. User taps Generate.
2. Local model produces an English passage.
3. Validate generated text.
4. Replacement engine analyzes the original passage.
5. Selected German/Russian substitutions are computed.
6. Mixed-language text is displayed.
7. Original text and replacement metadata are persisted.

The UI must remain responsive while inference is running.

Do not show unfinished or incorrectly aligned replacements.

### 9.2 Interactive Passage Rendering

Replaced words must be visibly distinguishable.

Assign a subtle, configurable appearance to each language.

Example:

German: one accent color.

Russian: another accent color.

Tapping a replaced span opens a popover, sheet, or contextual overlay containing:

- Original English expression
- Target-language expression
- Language
- Optional brief context or meaning
- Add to Vocabulary action

The renderer must support Cyrillic and German Unicode correctly.

Use attributed text rendering with accurate span hit-testing.

If native SwiftUI Text interaction is insufficient, use a minimal UIKit TextKit bridge through UIViewRepresentable.

Maintain accessibility support and dynamic type.

Do not use brittle overlays based on estimated pixel positions.

### 9.3 Study Screen

Show:

- Cards due today
- New cards available
- Deck picker
- Start Review action
- Review progress
- Completion state

Review interaction should be immediate and lightweight.

### 9.4 Settings Screen

Include:

- CEFR level
- Default text length
- Target languages
- Language weights
- Replacement density
- SRS daily limits
- Local storage usage
- Model information
- Open-source notices

Do not add unnecessary settings or experimental options to the main UI.

## 10. Performance and Memory

Optimize for the actual iPhone 13, not just an Apple Silicon Mac or simulator.

The simulator is useful for UI development but cannot establish real-device LLM performance.

Requirements:

- No inference on the main thread.
- Avoid simultaneous model instances.
- Keep context windows bounded.
- Avoid unnecessary model reloads.
- Release resources on memory pressure when appropriate.
- Avoid loading entire lexical databases into RAM.
- Cache only frequently accessed lexical entries.
- Use lightweight replacement representations.
- Support task cancellation.
- Keep database reads and writes off critical UI paths.

The model may remain loaded while generation is actively useful, but implement lifecycle management so backgrounding and memory pressure do not destabilize the app.

### 10.1 Performance Targets

Measure rather than assume.

Initial engineering targets:

- Interactive scrolling without noticeable lag.
- Word popup response perceptually immediate.
- Typical 100-word lexical substitution under 200 ms after data is available in memory.
- Generation as fast as realistically achievable without compromising B2/C1 quality.
- No crashes or jetsam termination during repeated generations.
- Stable operation under repeated Generate actions.

Record:

- Cold model load time
- Warm model load time
- Time to first token
- Tokens per second
- Time for a 100-word passage
- Peak memory footprint
- Thermal state
- Battery impact
- Lexical substitution duration

Test multiple consecutive generations, not only one fresh launch.

If the initial model performs poorly, benchmark alternatives and document a justified decision.

Never fabricate benchmark results.

## 11. Offline Guarantee

This application must remain functional with:

- Airplane mode enabled
- Wi-Fi disabled
- Cellular data disabled
- No user account
- No server connection
- No downloaded language resources

Required assets must ship inside the installed app.

The project may use internet access during development to retrieve dependencies, source weights, and licensed lexical datasets.

The distributed app must not require such access.

Do not add:

- Remote inference
- Telemetry SDKs
- Analytics SDKs requiring network access
- Cloud authentication
- Online translation services
- Mandatory online language-pack downloads
- Mandatory online model downloads

Audit the production target for networking dependencies and runtime network requests.

Test the app offline immediately after a fresh installation, not only after previous online initialization.

## 12. Suggested Repository Structure

LinguaFranca/
- AGENTS.md
- README.md
- LinguaFranca.xcodeproj
- App/
  - LinguaFrancaApp.swift
  - AppEnvironment.swift
- Features/
  - Generate/
  - Study/
  - Vocabulary/
  - Settings/
- Core/
  - Generation/
    - TextGenerationService.swift
    - GenerationRequest.swift
    - GenerationResult.swift
    - LlamaCppService.swift
  - Linguistics/
    - EnglishTextAnalyzer.swift
    - Tokenizer.swift
    - Lemmatizer.swift
    - SenseDisambiguator.swift
  - Replacement/
    - ContextualReplacementEngine.swift
    - CandidateSelector.swift
    - WeightedLanguageSelector.swift
    - ReplacementSpan.swift
    - ReplacementValidator.swift
  - Languages/
    - LanguagePack.swift
    - LanguagePackRegistry.swift
    - German/
    - Russian/
  - SRS/
    - SRSScheduler.swift
    - FSRSAdapter.swift
    - ReviewSession.swift
  - Persistence/
    - DatabaseManager.swift
    - Migrations/
    - Repositories/
- UIComponents/
  - InteractivePassageView.swift
  - VocabularyPopover.swift
  - LanguageSelector.swift
- Resources/
  - Models/
  - LanguagePacks/
  - Topics/
- Tools/
  - LexiconBuilder/
  - ModelPackaging/
- Tests/
  - GenerationTests/
  - ReplacementTests/
  - LanguagePackTests/
  - PersistenceTests/
  - SRSTests/
  - PerformanceTests/
- Documentation/
  - Architecture.md
  - ModelBenchmark.md
  - LanguagePackFormat.md
  - LexicalDataLicenses.md

The exact structure may be refined, but separation of responsibilities must remain clear.

Prefer testable Swift packages for pure logic where beneficial.

## 13. Required Testing

### 13.1 Generation Tests

Verify:

- B2 requests produce English passages.
- C1 requests produce English passages.
- Output contains no model-control tokens.
- Output stays within reasonable length bounds.
- No Markdown or unwanted instructions are returned.
- Cancellation works.
- Repeated generation does not leak native resources.

CEFR compliance cannot be proven by a simple word-count or vocabulary heuristic.

Evaluate an offline test set with human-reviewed quality criteria.

### 13.2 Replacement Tests

Test polysemy:

- Financial bank vs river bank
- Light as adjective vs noun
- Charge as payment vs accusation
- Right as correct vs direction
- Run as physical movement vs operating software

Test morphology:

- English plural nouns
- Past-tense verbs
- German gender and inflection
- Russian grammatical cases
- Russian verbal aspect

Test:

- Multiple target languages in one sentence
- Zero enabled languages
- Missing dictionary entries
- Ambiguous translations
- Overlapping candidates
- Multiword expressions
- Unicode correctness
- Punctuation preservation
- Repeated words with different contextual meanings
- Deterministic output with fixed seed

Test false friends, including English "actual" and German "aktuell".

A replacement must not change the intended meaning of the English sentence.

### 13.3 SRS Tests

Verify:

- Cards can be created and deleted.
- Decks persist across launches.
- Each review rating updates scheduling correctly.
- Due dates survive application restarts.
- Historical review logs remain intact.
- Schema migrations preserve study progress.
- FSRS calculations match validated reference cases.

### 13.4 Offline Tests

Fresh-install the app.

Enable airplane mode before the first launch.

Verify:

- Model loads.
- English generation works.
- German replacement works.
- Russian replacement works.
- Mixed-language replacement works.
- Vocabulary can be saved.
- Study sessions can be completed.
- All data persists across restarts.

## 14. Development Phases

Implement the project incrementally.

Each phase must produce working, testable code.

### Phase 1 — Native Project Foundation

- Create Xcode project.
- Configure Swift 6.
- Create base SwiftUI navigation.
- Integrate GRDB.
- Establish schema migrations.
- Define core protocols and data models.
- Set up unit tests.

Deliverable: Compiling native app with functional local persistence.

### Phase 2 — Local LLM Integration

- Integrate llama.cpp into the iOS target.
- Bundle a verified quantized model.
- Implement model load/unload lifecycle.
- Implement asynchronous inference.
- Add Generate interface.
- Display original English passage.
- Benchmark on physical iPhone 13.

Deliverable: Offline B2/C1 English generation using a real local model.

### Phase 3 — English Analysis and Lexical Resources

- Implement tokenizer and sentence segmentation.
- Implement English lexical analysis.
- Build lexicon ingestion tools.
- Package German and Russian lexical databases.
- Implement language pack registry.
- Create contextual sense selection and morphology adapters.
- Add translation validation tests.

Deliverable: Real local lexical lookup and contextual candidate ranking.

### Phase 4 — Toucan-Style Replacement

- Implement candidate selection.
- Implement language weighting.
- Implement replacement density.
- Implement reversible span mapping.
- Implement interactive text rendering.
- Implement contextual word popup.
- Connect replacement engine to generated passages.

Deliverable: One passage containing reliable German and Russian substitutions.

### Phase 5 — Vocabulary and SRS

- Implement vocabulary storage.
- Implement deck management.
- Add contextual Save Word action.
- Integrate validated FSRS scheduling.
- Implement review interface.
- Implement progress and due-card views.

Deliverable: Fully offline vocabulary collection and spaced repetition study.

### Phase 6 — Optimization and Release Readiness

- Run physical-device performance tests.
- Optimize inference and memory.
- Expand lexical coverage based on measured errors.
- Audit offline operation.
- Validate bundled asset licenses.
- Improve accessibility.
- Test repeated sessions and lifecycle transitions.
- Eliminate crashes and known data-loss bugs.

Deliverable: Stable and usable initial LinguaFranca application.

## 15. Agent Collaboration Rules

When implementing this project, agents must follow these rules:

1. Read this AGENTS.md before making architectural decisions.
2. Inspect the existing repository before adding new abstractions.
3. Keep changes focused on the current development phase.
4. Implement actual functionality rather than mock demonstrations.
5. Do not replace the on-device LLM with hardcoded passages as the final implementation.
6. Do not replace contextual translation with a static demonstration array as the final implementation.
7. Do not fake model benchmarks or report unexecuted tests as passing.
8. Write tests for all nontrivial language-processing algorithms.
9. Prefer small, composable types and explicit protocols.
10. Keep UI code separate from inference and translation logic.
11. Preserve database migrations and backward compatibility.
12. Avoid unrelated refactors.
13. Do not introduce cloud services.
14. Keep any new language support generic wherever possible.
15. Do not silently downgrade product requirements.
16. Document unavoidable limitations accurately.
17. Maintain buildable checkpoints as work proceeds.
18. Prefer substantive implementation over unnecessary scaffolding.

When code cannot be built because Xcode, signing, or an iOS device is unavailable, state the exact limitation.

Do not claim physical-device validation based on simulator tests.

For each substantial implementation milestone, report:

- Files added or modified
- Functionality implemented
- Tests performed
- Tests not performed
- Remaining blockers
- Next recommended step

Do not stop after creating empty folders, protocols, or placeholder screens when a functional implementation is feasible.

## 16. Definition of Done

The initial application is complete only when:

1. It launches successfully on iPhone 13.
2. Its bundled local LLM generates useful B2/C1 English passages.
3. Generation works with no internet connection.
4. German context-sensitive replacements work.
5. Russian context-sensitive replacements work.
6. Both languages can be mixed in the same passage.
7. Tapping a replacement reveals its original English expression.
8. Users can save vocabulary to custom decks.
9. SRS reviews update and persist correctly.
10. All databases and lexical resources are available offline.
11. The application does not exceed practical device memory limits.
12. Core logic is covered by automated tests.
13. No mandatory server, account, or remote API exists.
14. The architecture supports future languages through the LanguagePack abstraction.
15. Performance and linguistic-quality limitations have been measured and documented.

A working application with conservative, accurate substitutions is preferable to a visually impressive prototype that frequently teaches incorrect translations.

## 17. Immediate Instruction to Coding Agents

Begin implementation with Phase 1.

First establish the native Xcode project, module boundaries, persistence layer, and test infrastructure.

Then proceed to Phase 2 and integrate genuine on-device text generation.

Do not defer the core LLM integration until the end of the project.

Once the local generation pipeline works, build the language pack and contextual replacement engine, followed by the SRS subsystem.

Make reasonable implementation decisions autonomously while respecting the mandatory requirements in this document.

The overriding engineering priorities are:

1. Correctness of contextual vocabulary substitutions.
2. Fully offline operation.
3. Stable iPhone 13 performance.
4. Quality of generated English.
5. Extensible language architecture.
6. Reliable spaced repetition.
7. Clean native user experience.

Build LinguaFranca as a real offline language-learning system.
