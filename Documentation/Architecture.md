# Architecture

`SwiftUI → AppEnvironment → local inference actor / replacement engine / database actor`

LinguaFrancaCore owns domain models, immutable English passages with reversible UTF16 spans, settings migration, contextual processing and GRDB persistence. LinguaFrancaInference owns native llama.cpp handles, verified model loading, serialized generation, cancellation and cleanup away from the main actor. Runtime cloud inference, networking and telemetry are absent.

The LLM generates English only. ContextualReplacementEngine analyzes that original and queries generic LanguagePack implementations. LanguagePackRegistry discovers versioned manifests and shares one bundled English POS model across targets. New languages use the same frequency UI/allocation; they may require new morphology data or adapters.

NaturalLanguage supplies segmentation. A bundled averaged perceptron supplies POS even without optional OS English tagging assets. Native Swift predictions match fixed vectors from original NLTK 3.9.2 classes. Noun lemma candidates require actual dictionary senses, and target plurals require attested forms in SQLite. Unknown and ambiguous forms are skipped.

Sense ranking uses POS, contextual gates for high-risk polysemes, gloss keywords and ambiguity checks. Repeated words use local context; unique words can use their sentence. Hyphenated compounds are not partly translated. Subject forms are not substituted for object/reflexive pronouns merely because their lemmas match.

Per-language frequency refers to source word tokens. Combined requests above 50% are proportionally scaled. Seeded selection first spreads words, then at high density permits pairs but never three consecutive replacements. No overlaps, destructive source changes or translation chaining occur. Actual density can be below the target and is persisted as a diagnostic.

Remix atomically updates metadata/spans for the same English original. Saved vocabulary is independent of later remixes. Refresh revisions prevent stale async UI updates. The legacy preview identity preserves earlier user lists/settings; only explicitly tagged former sample readings are removed.

Inference verifies the selected 532,517,120-byte GGUF before native loading. Each generation owns and releases context/sampler resources; model reuse/unload are serialized. The Qwen3.5 chat template supplies an empty thinking block. Bounded structural validation/retry cannot certify semantics or CEFR.

SRS tables retain card state, history and scheduler version. Validated FSRS6 review sessions remain future work. Case, agreement, full verbs/adjectives and multiword replacement are also open; displayed mixed text is an English frame with lexical insertions.
