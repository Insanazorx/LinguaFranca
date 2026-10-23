# Selected-model validation — 2026-10-23

At the user's explicit request the app uses **Qwen3.5-0.8B Q4_K_M**, not the original Qwen3-1.7B plan. Only the selected model is bundled. A comparative Qwen3-1.7B quality benchmark has not run.

- GGUF distribution: Unsloth, revision `6ab461498e2023f6e3c1baea90a8f0fe38ab64d0`.
- Source model revision: `2fc06364715b967f1860aea9cf38778875588b17`.
- Verified file size: 532,517,120 bytes.
- Verified SHA-256: `bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517`.
- License: Apache 2.0. Bundled attribution and full notices are included.
- Runtime: llama.cpp b11829, commit `184f6536024668e8908ab8c86033d56708e62b40`. Simulator slice built from the same pinned source; native device slice is included.
- Context 2048, generation cap 320 tokens, batch 64, at most four threads, temperature 0.7, top-p 0.9, repeat penalty 1.05. ChatML uses a closed empty thinking block. Python is not part of the app runtime.

## Executed real generation

| Environment | Request | Words | Total seconds | Attempts |
|---|---|---:|---:|---:|
| Development Mac | B2 daily life | 148 | 3.11 | 1 |
| Development Mac | C1 technology | 105 | 5.21 | 2 |
| Development Mac | C1 travel | 107 | 6.11 | 2 |
| iPhone 13 simulator app | C1 travel | 164 whitespace words | 20.71 | 1 |

The recorded simulator run took 1.068 seconds to load and 5.662 seconds to first token; seed 1475087561. Linguistic tokenization counts that passage as 165 tokens. Timings include the recorded runtime boundaries and are not physical iPhone measurements. Evidence files retain the generated text and metadata.

Output quality is uneven: examples include an implausible fork/tea action and generic figurative travel prose. Basic English/length/control-token validation cannot establish CEFR level, coherence or teaching quality. Human quality review remains open.

## Open device measurements

Physical iPhone 13 cold/warm loading, generation, peak memory/jetsam, thermal state, battery use, repeated runs/cancellation, fresh first-launch airplane-mode and batch 32 versus 64 comparison have not run. GGUF size is not runtime memory usage. Physical iPhone 13 installation/signing and initial app launch have now completed; on-device inference measurements remain the next gate.

Final end-to-end simulator check: a new C1 Education request produced 111 whitespace words (112 linguistic tokens) in 14.466 seconds, first token 5.297 seconds and load 1.128 seconds. The app immediately mixed 25 tokens (22.3%; German 13, Russian 12), retained the original and persisted both readings. Saved vocabulary count was 7, including the newly saved Tasche/bag item. This lower density is a measured coverage limit, not a 50% result. Evidence: Evidence/LinguaFranca-app-final-generation.json and LinguaFranca-final-reading.png.

## Physical installation update — 2026-10-23

Signed Debug build 0.1.0 (1), bundle com.linguafranca.app, installed successfully on the user’s iPhone 13 running iOS 26.6.1. Native code-signature validation and app-bundle checksum verification passed. The development profile matches the connected device, team and application entitlements and expires on 2026-10-30 at 14:54 Istanbul time. The user explicitly authorized certificate/profile creation. iOS initially denied launch during trust validation; after the user trusted their own developer certificate in phone settings, they confirmed the application opened. No reinstall or source-code change was needed to resolve that denial. This records app installation/launch only, not measured physical-device model generation or release readiness.
