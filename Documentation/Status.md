# Working test checkpoint — 2026-10-23

Project: `/Users/insanazor/Desktop/LinguaFranca`. This is the first real-model / mixed-language test build, not a completed release.

## Implemented

- Real bundled Qwen3.5-0.8B Q4_K_M, selected explicitly by the user, executed locally through pinned llama.cpp. No dummy reading fallback remains. Original user readings, lists and vocabulary persist.
- Native Swift 6 / SwiftUI navigation, GRDB persistence and interactive vocabulary saving.
- Independent saved frequency sliders for every registered target language; German and Russian may run together. Psycho requests 50%, with an overall 50% ceiling and actual-density reporting. Existing preferences migrate.
- Indexed, licensed WikDict dictionaries, source-attested noun plurals, a bundled English POS model executed in Swift, contextual sense filtering and reversible UTF-16 spans. No optional Apple language download is required for POS analysis.
- Remix reprocesses the unchanged English original without generating again. Saved vocabulary is independent of later remixes.
- Fixed missing embedded-framework search path, missing bundled dictionaries, incorrect travel sense of trip, object/reflexive pronouns, hyphenated partial replacements, bound suffix replacements and an odd-token density ceiling.

## Verified

32 package tests passed: 28 core and 4 inference tests. Simulator and unsigned iPhone builds succeeded. Actual built bundles passed resource, database integrity, checksum and inference search-path checks. Runtime source audit found no networking API usage.

The actual iPhone 13 simulator app loaded the previous genuine local-model reading, applied saved German/Russian Psycho settings and displayed 52 substitutions out of 165 linguistic tokens (31.5%, rounded to 32% in UI). English remained intact. Tapping Tasche revealed bag and the source sense; Save Word changed to Saved to vocabulary. Both language controls and their saved frequencies were verified.

## Changed areas

`Core/Domain/Models.swift`, `Core/Languages/`, `Core/Persistence/`, `App/AppEnvironment.swift`, `Features/Generate/`, `Features/Settings/`, `UIComponents/`, `Tests/CoreTests/`, `Tests/Fixtures/`, `Resources/LanguagePacks/`, model metadata and license notices, project generation, morphology preparation and app-bundle verification tools. See Architecture.md and LanguagePackFormat.md for contracts.

## Remaining gates

- Physical iPhone 13 installation and initial launch completed. The user enabled Developer Mode, signed into Xcode, authorized development signing and trusted their own developer certificate on the phone. The initial launch denial was the missing iOS developer trust approval; the user confirmed that the app opened after granting it. Physical inference/performance and fresh-install airplane-mode validation remain open.
- Physical iPhone 13 peak memory, thermal/battery impact, repeated inference/lifecycle stress and fresh-install airplane-mode testing remain unmeasured.
- CEFR is a prompt target; generated prose may be awkward. Replacement sense scoring and POS tagging remain heuristic. Relative-clause classification, figurative language, case/agreement, dependent phrases, verbs/adjectives and general multiword translation need further linguistic evaluation. Psycho cannot guarantee 50% safe coverage for every passage.
- Validated FSRS 6 scheduling and review sessions remain pending; the Study screen does not claim a working scheduler. Vocabulary, lists and historical review records are preserved.

Next step: connect the user's iPhone, resolve signing using their existing Xcode account, install this test build and measure the real-device behavior before making performance or offline-release claims.

Final end-to-end simulator check: a new C1 Education request produced 111 whitespace words (112 linguistic tokens) in 14.466 seconds, first token 5.297 seconds and load 1.128 seconds. The app immediately mixed 25 tokens (22.3%; German 13, Russian 12), retained the original and persisted both readings. Saved vocabulary count was 7, including the newly saved Tasche/bag item. This lower density is a measured coverage limit, not a 50% result. Evidence: Evidence/LinguaFranca-app-final-generation.json and LinguaFranca-final-reading.png.

## Physical installation update — 2026-10-23

Signed Debug build 0.1.0 (1), bundle com.linguafranca.app, installed successfully on the user’s iPhone 13 running iOS 26.6.1. Native code-signature validation and app-bundle checksum verification passed. The development profile matches the connected device, team and application entitlements and expires on 2026-10-30 at 14:54 Istanbul time. The user explicitly authorized certificate/profile creation. iOS initially denied launch during trust validation; after the user trusted their own developer certificate in phone settings, they confirmed the application opened. No reinstall or source-code change was needed to resolve that denial. This records app installation/launch only, not measured physical-device model generation or release readiness.

## Source-only repository and bootstrap — 2026-10-23

Added Tools/bootstrap.py, Tools/build.py, build.sh, seven build-tool regression tests, source-only ignore rules, an extended dependency lock, documented commands and a manually dispatched GitHub Actions workflow. The Xcode project generator now accepts an Apple team and preserves an existing local choice; generated projects are ignored by Git. No app behavior or on-phone data was changed.

Executed against a clean directory exported from only the Git-tracked source files, with no Vendor directory, GGUF, SQLite packs, POS weights or generated Xcode project: all dependencies restored, a fresh llama.cpp simulator slice compiled and merged with the official device/Mac slices, lexical packs regenerated, model/POS assets verified, project generated, 7 build-tool tests passed, 32 Swift tests passed (28 core + 4 inference), simulator app built successfully, and actual bundle checksum/resource verification passed. Regenerated German/Russian pack hashes match the previous validated packs. A subsequent --offline --bootstrap-only run verified and reused every dependency successfully.

Existing pinned source archives and model bytes seeded the download cache to avoid downloading the large model again. The pipeline fetched the missing pinned dawg2-python wheel from PyPI over HTTPS and verified it. This validates a source-only restore and real native build using the cache; it does not claim all upstream bytes were redownloaded during this run. macOS/Xcode/Python and CMake were already installed, so automatic installation of missing CMake was not exercised. No remote GitHub Actions run is claimed; that workflow is available for manual dispatch.

## Temporary reading sessions and vocabulary contrast — 2026-10-23

The latest user request replaces the earlier persistent-reading behavior: generated readings and Remix metadata now live only in process memory. Backgrounding retains them; fully closing the app or OS process termination clears them. Migration v2 removes the old reading archive while preserving vocabulary, examples, lists, settings and SRS history. New saved vocabulary retains its example sentence.

Added international-lookalike filtering, enabled-language-aware English prompts using actual local dictionary hints, distinct scenario planning and post-inference duplicate checks. Each inference attempt still owns a fresh native context. Final validation: 41 Swift tests + 7 build-tool tests passed; offline simulator build and app-bundle checksums passed; installed and launched the final package in iPhone Duo / iOS 27.1. The simulator retained a reading across background/foreground and cleared it after process restart. Full implementation/changed files/test limits: SessionReadings.md. Etymology and semantic uniqueness are not proven; small-model prose/length quality and physical-device validation remain open.

## Literary formats, focused practice and local audio — 2026-10-23

Added six genre choices, combinable structure/content/actions practice and mixed/original sentence speech in the word sheet. Attested German/Russian practice forms are packaged in lf3 dictionaries. 59 automated tests, offline simulator build and bundle verification passed. Real local model execution passed all six literary formats after adding native constraints for dialogue/play/poem. The simulator generated a 90-word focused dialogue; the word menu's English/German, English/Russian and original English playback controls were exercised, normal completion and Stop were verified, and native AudioQueue buffer production was observed. Simulator logs also recorded eight underflow/silence-insertion events. Physical phone audio quality remains unverified; grammar coverage remains conservative. See WritingFocusSpeech.md and Evidence/Writing-focus-speech-validation.json for files, measurements and limits.

## Aggressive and vocabulary-language writing — 2026-10-23

Replaced Domain focus with frequency-independent Aggressive, added atomic case-aware preposition/complement practice, fixed conditional/relative-clause ambiguity, grouped list words by language and added real local monolingual vocabulary writing. lf4 adds attested noun case tables. 68 automated tests, offline build and bundle checks passed; four real model batches passed language and word-coverage validation. Small-model grammatical errors remain observable and are not certified by these checks. See AggressiveAndVocabularyPractice.md and Evidence/Aggressive-vocabulary-validation.json.

## Aggressive reliability checkpoint — 2026-10-24

Current source passes 68 Swift tests and the offline simulator build/bundle checks. Full real-model Aggressive coverage remains incomplete; German structure passed one profile, Russian structure and both action profiles failed the current native suite. The six-case semantic diagnostic passed three cases after the additional meaning check. Generate now preserves visible English drafts; word-only pronunciation is implemented but latest UI/audio validation remains pending. See AggressiveReliability.md for changes, executed tests and limitations.


## 24 October 2026 — Aggressive 2B and FSRS cards

Mode-specific Qwen3.5-2B Aggressive flow, five-language automatic pair/triple allocation, corpus-constrained Syriac, and FSRS 6 flip/swipe cards are implemented. 83 core + 4 inference Swift tests, 14 Python tests and the offline build/bundle checks pass. Actual Mac Arabic/Hebrew/Syriac generation and isolated simulator swipe/persistence checks pass. Physical iPhone 13 2B profiling remains pending. See Aggressive2BAndSRS.md. No commit/push in this milestone.


## 24 October 2026 — Dictionary and voluntary practice

2D card dragging, unrestricted list/individual practice, hidden internal FSRS states and a separate Forgotten words list are implemented. Dictionary uses all five bundled packs with 346,547 searchable senses/lexemes/roots, native forms, source details and saving. Semitic Roots is accessible inside Dictionary. 88 core + 4 inference Swift tests, 16 Python tests, offline build and bundle checksums pass; simulator gesture/forgotten/dictionary-save flows were exercised in an isolated library. No physical-device validation in this milestone. See DictionaryAndFreePractice.md. No commit/push.


## 24 October 2026 — Separate native Mac target

Added LinguaFranca Mac, a native macOS target with its own UI sources under Mac/, sharing Core, Inference and bundled offline assets. iOS target membership excludes all Mac presentation files; iOS features and installed app were preserved. The desktop app retains five dictionaries, Semitic tools, both generation modes, vocabulary and unrestricted FSRS practice, with native sidebar/settings, mouse dragging and keyboard shortcuts.

88 core + 4 inference Swift tests and 17 Python build/data tests passed. Native Debug/Release builds, offline asset checks, native Mach-O platform and signing validation passed. The installed Release and llama framework share the existing Apple Development team; sandbox and library validation remain enabled. Actual native UI generation, cards, dictionary, saving and session persistence were exercised. One-time read-only simulator library backup copied one word/list/card and three review logs into the absent Mac library. The final model-unload-on-quit handler is implemented but not re-exercised while the current user reading is open. See MacApp.md. No commit/push or iOS installation.


## 24 October 2026 — Shared book application icon

Replaced the Mac leaf icon with an original closed-book drawing matching the opening-screen book motif, and added the same artwork to the iOS AppIcon asset catalog. Tools/prepare_mac_icon.swift renders both platforms reproducibly during build.sh: transparent outer Mac margins and a full-bleed, opaque 1024px iOS source. Existing application behavior was preserved. Mac Release and iOS simulator builds and bundled icon metadata checks passed; iOS source dimensions/absence of alpha were verified. The installed Mac icon was updated and re-signed without closing its current reading. Physical iPhone 13 was unavailable.


## 24 October 2026 — Continuous portrait card practice

Study now shows only a 2:3 portrait card with random yellow/green/blue/red coloring and an in-card exit control. Tap/2D drag remain; counters and separate rating panels are removed. Selected cards repeat until exit, prioritizing due FSRS learning/reviews and allowing balanced early repeats when no card is due. Mac uses the main canvas without a sidebar; iOS uses full-screen presentation.

The shared queue keeps fresh saved snapshots and selected-list membership. A real UI retry exposed sub-microsecond Date rounding across SQLite; returning/logging the persisted card fixes false stale-write errors without relaxing transaction guards. 94 core + 4 inference Swift tests and 17 Python tests passed, including 200 uninterrupted simulated reviews and fractional-time/idempotency regressions. Mac Release and iOS simulator builds passed resource/signing checks. Native UI verified portrait presentation, flip, vertical spring return, eight repeated swipes over two cards, persisted reviews and explicit exit. Simulator restored to the normal library; Mac updated and left on Study. No physical iPhone test or commit/push. See ContinuousStudy.md.


## 25 October 2026 — Optional Russian audio and saved readings

Listen → Russian prepares a full target-language reading with the existing 2B model, then unloads the LLM and speaks offline with the user-selected Denis voice. Balanced generation is unchanged. Mixed/Russian views, optional actual-audio word timestamps, pause/resume/stop and an opt-in saved-text library are implemented on both platforms. Voice/alignment weights load only on explicit playback and are released on pause, Stop, completion, failure, navigation away and lifecycle teardown. Unsaved texts remain ephemeral; saved vocabulary and FSRS histories remain independent.

100 Core + 5 inference Swift tests and 17 Python tests passed for this milestone. Mac Release and simulator builds, bundled hashes and Mac signatures passed. Real 2B diagnostics and a 13-sentence regression ran on the Mac; the long iOS trial exposed truncated JSON/English residue, corrected with bounded retry and Russian output constraints. Native Mac saving/relaunch, playback, markers and navigation were exercised. Simulator playback/marker/pause/navigation used the real Mac translation in an isolated test library, not fabricated speech or a production fixture. Russian speech on the physical phone remains unmeasured. See RussianReading.md for files, licenses and limits. No commit/push.


## 25 October 2026 — Physical iPhone 13 memory recovery

Physical jetsam reports confirmed vm-pageshortage in the 2B workflow. Added bounded Metal/file-backed execution, smaller native batches, prompt-sized contexts without shortening output, explicit autorelease scopes and idle large-model release. Kernel-critical pressure/low dirty-memory headroom interrupt safely; ordinary warnings trim optional resources rather than always discarding active inference. Long paired outputs retain complete mappings and repair only missing occurrences. Audio is unloaded before Remix.

104 Core + 9 inference Swift tests passed, as did the signed physical Release build, bundle hashes/signature and library integrity checks. CPU and initial partial-GPU timings are recorded separately for different passage lengths. The user reported that final Generate completed quickly and reported Remix completion, then requested no further Remix work. Exact final timing/peak was not retrieved, so no numeric speedup is claimed. Existing 4 words, 1 list, 4 cards and two explicitly saved readings were preserved in safety copies. System profiling was explicitly authorized and kept local; the final acceptance run had heavy recording/mirroring closed. See iPhone13Memory.md and the sanitized evidence JSON. Work is being committed/pushed at the user's request.
