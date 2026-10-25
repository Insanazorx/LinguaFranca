# iPhone 13 inference memory — 25 October 2026

## Problem and resulting behavior

The user's physical iPhone 13 repeatedly terminated LinguaFranca when entering the 2B Aggressive workflow or applying Aggressive Remix. Three retrieved jetsam reports name LinguaFranca as the largest foreground process and report `vm-pageshortage`, at roughly 1.5 GB of accounted pages. Those reports precede the user's update from iOS 26.6.1 to iOS 27.0.1; they are not a controlled same-OS before/after benchmark.

Qwen3.5-2B Q4_K_M and its existing verified weights are retained. Balanced's generation and lexical method remain unchanged. On physical iOS devices with at most 4 GiB RAM, large models use a bounded 16-layer Metal allocation, file-backed weights, no additional CPU weight repacking, and a physical micro-batch of 16. Native contexts fit the actual prompt plus the entire requested output budget, rounded within the existing 512–4096 bounds. No output budget is silently shortened.

Model hashing drains Foundation temporaries after every 4 MiB chunk. Native model loading, inference and destruction also have explicit autorelease scopes. Large Aggressive models are released when a complete Generate or Remix action finishes on constrained phones. Remix releases optional narration resources before inference. Generation/audio keep the display awake only while actively useful, so automatic screen locking does not silently cancel a long job.

Memory warnings are differentiated from kernel-critical pressure. A normal warning frees optional audio and idle models; active inference continues only with known headroom of at least 256 MiB and a footprint below 1280 MiB. Unknown/low headroom and kernel-critical events stop safely, unload resources and select the CPU fallback for subsequent constrained-model work in that process. Remaining headroom uses Apple's `os_proc_available_memory()`; it is the process's dirty-memory allowance, not total free device RAM. Critical system pressure is handled independently through Dispatch.

Long paired JSON output can end partway through the replacement list. Previously that discarded every mapping and regenerated them all in small repair batches. Prefix recovery now preserves every complete, decoded mapping, including quoted/escaped Unicode strings. Existing span, script, overlap and attested-form checks still apply; only missing or invalid occurrences are repaired. Incomplete objects are never translated as if complete.

## Executed validation

- 104 Core + 9 inference Swift tests passed. New coverage includes constrained/default/CPU-fallback policies, context budget/overflow bounds, warning versus critical/low-budget decisions, complete mapping-prefix recovery and every character-boundary truncation of an escaped Unicode fixture. The earlier 17 Python build/data tests passed; their tools were unchanged by this memory fix.
- The final signed Release built for the connected iPhone 13, passed actual installed-bundle asset/hash checks and signature validation, and was installed over the existing app. SQLite quick checks passed; 4 vocabulary items, 1 deck and 4 cards were preserved. The pre-update review count was zero. Two explicitly saved readings were present in the later safety copy.
- CPU-only baseline: 96 whitespace words, 31/31 selected expressions, 1207 total tokens, 303.117 seconds. Model loading took 16.823 seconds and time to first token was 37.871 seconds. The raw inference's sampled footprint peak was 229,788,664 bytes. Later repair calls are not included in that particular peak field.
- Initial partial-GPU experiment with CPU KV/recurrent state: 196 whitespace words (198 linguistic tokens in the UI), 81/81 expressions and 602.994 seconds. This longer passage is not directly comparable to the 96-word baseline. Its raw inference sampled 242,273,320 bytes; a separate first-60-second Activity Monitor window recorded 308.7 MiB footprint and 673.3 MiB resident peak. The trace does not cover the complete ten-minute action.
- Moving the offloaded layers' KV/recurrent state to Metal reduced the native graph from 70 splits to 2. An intermediate run still stopped because the previous handler cancelled on every UIKit memory warning. The 120-second trace recorded a 292.1 MiB footprint peak before cleanup and 86.7 MiB at the end. This prompted the final pressure classification above rather than disabling protection.
- With the final pressure policy installed and heavy profiling/live phone mirroring closed, the user explicitly reported that Generate completed and was fast. They also reported Remix completion, then requested no further Remix work. These are physical-device user acceptance results. The final successful passage was not in the retrieved saved snapshot, so an exact final latency, speedup or footprint is not claimed.

Model buffer mappings, process footprint and resident memory are different measurements. CPU/Metal mappings may alias the same read-only file pages; their sizes must not be added together and presented as measured RAM consumption. Short traces and sampled counters are not a continuous lifetime peak.

The user explicitly authorized general system profiling after the first broad request was rejected by automatic approval review. Raw traces and library safety copies stay local under `/private/tmp`; only application-specific summaries belong in the repository. The final acceptance run used the app's own counters without the heavy profiler or live device screen.

## Files and limits

Added: `Inference/InferenceMemoryPolicy.swift`, `Tests/InferenceTests/InferenceMemoryPolicyTests.swift`, `Tests/CoreTests/AggressivePrefixRecoveryTests.swift`, this document and the sanitized evidence JSON.

Updated: `Inference/LlamaCppService.swift`, `Inference/ModeGenerationService.swift`, `App/AppEnvironment.swift`, `App/LinguaFrancaApp.swift`, `Core/Generation/AggressiveGeneration.swift`, README, architecture and status documentation. Persistence migrations, vocabulary and FSRS algorithms were not changed by this fix.

Logs remain in ignored `.bootstrap/logs/`: `iphone13-pressure-policy-tests.log`, `iphone13-pressure-policy-build.log`, `iphone13-pressure-policy-assets.json` and the earlier CPU/GPU experiment logs. Sanitized measurements: `Documentation/Evidence/iPhone13-memory-validation.json`.

Sustained thermal/battery behavior, all language combinations on the physical phone, and fresh-install airplane-mode testing were not repeated. Russian narration on the physical phone was not benchmarked. Severe system pressure can still legitimately interrupt work; no app can promise immunity to iOS termination. Next useful validation is ordinary reading on this installed version, recording any reproducible failure without extending the completed Remix experiment.
