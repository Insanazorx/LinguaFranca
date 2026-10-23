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
