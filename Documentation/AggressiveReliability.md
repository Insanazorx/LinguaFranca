# Aggressive reliability checkpoint — 2026-10-24

The requested universal, contextually correct Aggressive coverage is **not finished**.
The current source builds; this is an engineering checkpoint, not a release-quality claim.

## Implemented changes

- `Core/Languages/`: repaired dictionary POS normalization, expanded source-attested verb forms,
  auxiliary/progressive phrases, indirect-question constructions, whole-expression lookup,
  spatial preposition selection and optional bounded classification of existing dictionary senses.
  Classifier output is a dictionary option number and can never supply free-form translation.
- `ContextualReplacementEngine.swift`: selected-token coverage and explicit unresolved spans;
  Aggressive has no frequency/spacing cap. Unsupported phrases are available as generation feedback.
- `Core/Generation/`, `Inference/`: strengthened prompts for extreme selected-feature density and
  present-tense actions; removed word-count guidance from English prose prompts. Each inference
  context is fresh. An additional meaning check rejects inconsistent lexical classifications.
- `App/AppEnvironment.swift`, `Features/Generate/`: valid English appears before translation;
  cancellation/errors preserve that text, with explicit processing/incomplete status. Retries are
  bounded and grouped into one visible reading per Generate action.
- `UIComponents/`, `Features/Vocabulary/`: removed sentence-reading controls; the word sheet
  pronounces only the selected target expression using its target language.
- `Tools/prepare_language_packs.py`, `Tools/prepare_practice_forms.py`, dependency lock and notices:
  reproducible licensed lexical normalization and Kaikki/Wiktionary German verb paradigms (lf5).
- `Tests/CoreTests/AggressiveRegressionTests.swift`, build-tool tests and
  `Tools/ModelSmoke/RegressionChecks.swift`: coverage, meaning, inflection, visibility, pronunciation
  and real local-model regression checks.

## Executed validation

- Latest `swift test`: **64 core + 4 inference tests passed**.
- `./build.sh --test --offline`: passed, including Python build tests, Swift tests, simulator build
  and bundled-resource/checksum verification.
- Sixteen curated German/Russian coverage cases pass, including can, progressive/past, do-negation,
  writes, conjunctions, spatial relations and genitive phrases. These cases do not establish general
  prose coverage or linguistic correctness.
- Real Mac-host model generation, four profile/language combinations, up to three attempts each:
  German structure reached complete coverage on attempt three; Russian structure, German actions
  and Russian actions did **not**. The model still emits past tense/participles despite instructions.
- A six-case real model semantic diagnostic after the second meaning check passed three cases.
  It correctly rejected literal `moved in unison`, but temporal `since` and some `as` meanings remain
  unreliable or rejected. The full passage suite has not been rerun after the final conservative
  grammar guards. Do not label its earlier results as final-build success.

Logs are under the main project's `.bootstrap/logs/`: `aggressive-fix-tests.log`,
`aggressive-fix-build.log`, `aggressive-native-quick-v2.json`, and `aggressive-sense-check-v3.json`.

## Remaining work

The principal blockers are model adherence, general sense reliability and unsupported agreement,
participial/compound expressions and noun-phrase morphology. A generated reading can still remain
an explicitly incomplete English draft; it is never represented as a completed 100% Aggressive
translation. Latest popup/audio UI and repeated generation have not been validated in the simulator.
No physical iPhone 13 performance, memory, audio or fresh-install offline validation is claimed.
Next step is to improve these actual-model failures before publishing this milestone as ready.
