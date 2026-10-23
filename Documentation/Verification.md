# Verification ledger — 2026-10-23

## Automated checks executed

- Swift package: 32 tests passed (28 core, 4 inference). Tests cover persistence and migration, vocabulary/list behavior, preserved history, source/rendered Unicode spans, deterministic allocation and density bounds, zero/missing languages, generic language codes, polysemy, function-word context, subject/object pronouns, compound exclusions, source-attested noun plurals and ambiguity, bound-morpheme exclusions, the bundled English POS model against original NLTK reference predictions, and inference asset/lifecycle/output validation.
- iPhone 13 simulator app build: succeeded with real llama.cpp simulator slice and real model.
- iPhone device app build: succeeded with signing disabled. This is not an installed phone build.
- Both actual built app bundles passed `Tools/verify_app_bundle.py --checksums`: one selected GGUF, expected SHA-256, embedded llama framework and search path, German/Russian SQLite integrity and manifest hashes, offline English POS assets and hashes, source notices and CC BY-SA 3.0/4.0 license files.
- Development Python tools parse successfully. Runtime-source search found no URLSession, URLRequest, Network.framework, CFNetwork, telemetry or cloud inference API.

## Interactive checks executed

The genuine local-model Travel C1 reading was retained across app updates. Independent German/Russian controls were dragged to Psycho and saved; stored values were 0.5 each, normalized to a combined 0.5 ceiling. Remix used the actual bundled POS model and dictionaries: 52/165 tokens, German 26 / Russian 26. UI reports 32% actual against 50% target. Tapping Tasche showed bag and flexible-container sense; saving changed the button to Saved to vocabulary. Original English was not overwritten.

The same original text was processed by the independent smoke tool: Gentle 16/165 (9.7%), Medium 33/165 (20%), Psycho 52/165 (31.5%). Machine-readable output is in Evidence/LinguaFranca-frequency-comparison.json. Dictionary coverage and confidence limits apply; these counts do not certify every lexical choice.

## Genuine inference evidence

Three host generations and an actual simulator-app generation are recorded in Evidence/Qwen3.5-local-generation.json and Evidence/Qwen3.5-app-generation.json. The original simulator evidence predates language-pack wiring; it is retained as inference evidence, not as the final replacement state. No hardcoded passage was substituted for a model result.

## Not yet executed

Physical installation and launch are now verified. No physical-device inference/performance benchmark, fresh-install airplane-mode test, validated FSRS review cycle, reference FSRS vectors, full linguistic quality review, or long repeated generation/memory-pressure stress run is claimed. Simulator and Mac timings are not iPhone timings.

Final end-to-end simulator check: a new C1 Education request produced 111 whitespace words (112 linguistic tokens) in 14.466 seconds, first token 5.297 seconds and load 1.128 seconds. The app immediately mixed 25 tokens (22.3%; German 13, Russian 12), retained the original and persisted both readings. Saved vocabulary count was 7, including the newly saved Tasche/bag item. This lower density is a measured coverage limit, not a 50% result. Evidence: Evidence/LinguaFranca-app-final-generation.json and LinguaFranca-final-reading.png.

## Physical installation update — 2026-10-23

Signed Debug build 0.1.0 (1), bundle com.linguafranca.app, installed successfully on the user’s iPhone 13 running iOS 26.6.1. Native code-signature validation and app-bundle checksum verification passed. The development profile matches the connected device, team and application entitlements and expires on 2026-10-30 at 14:54 Istanbul time. The user explicitly authorized certificate/profile creation. iOS initially denied launch during trust validation; after the user trusted their own developer certificate in phone settings, they confirmed the application opened. No reinstall or source-code change was needed to resolve that denial. This records app installation/launch only, not measured physical-device model generation or release readiness.

## Source-only repository and bootstrap — 2026-10-23

Added Tools/bootstrap.py, Tools/build.py, build.sh, seven build-tool regression tests, source-only ignore rules, an extended dependency lock, documented commands and a manually dispatched GitHub Actions workflow. The Xcode project generator now accepts an Apple team and preserves an existing local choice; generated projects are ignored by Git. No app behavior or on-phone data was changed.

Executed against a clean directory exported from only the Git-tracked source files, with no Vendor directory, GGUF, SQLite packs, POS weights or generated Xcode project: all dependencies restored, a fresh llama.cpp simulator slice compiled and merged with the official device/Mac slices, lexical packs regenerated, model/POS assets verified, project generated, 7 build-tool tests passed, 32 Swift tests passed (28 core + 4 inference), simulator app built successfully, and actual bundle checksum/resource verification passed. Regenerated German/Russian pack hashes match the previous validated packs. A subsequent --offline --bootstrap-only run verified and reused every dependency successfully.

Existing pinned source archives and model bytes seeded the download cache to avoid downloading the large model again. The pipeline fetched the missing pinned dawg2-python wheel from PyPI over HTTPS and verified it. This validates a source-only restore and real native build using the cache; it does not claim all upstream bytes were redownloaded during this run. macOS/Xcode/Python and CMake were already installed, so automatic installation of missing CMake was not exercised. No remote GitHub Actions run is claimed; that workflow is available for manual dispatch.
