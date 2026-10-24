# Architecture

`SwiftUI → AppEnvironment → local inference actor / replacement engine / database actor`

LinguaFrancaCore owns domain models, immutable English passages with reversible UTF16 spans, settings migration, contextual processing and GRDB persistence. LinguaFrancaInference owns native llama.cpp handles, verified model loading, serialized generation, cancellation and cleanup away from the main actor. Runtime cloud inference, networking and telemetry are absent.

The LLM generates English only. ContextualReplacementEngine analyzes that original and queries generic LanguagePack implementations. LanguagePackRegistry discovers versioned manifests and shares one bundled English POS model across targets. New languages use the same frequency UI/allocation; they may require new morphology data or adapters.

NaturalLanguage supplies segmentation. A bundled averaged perceptron supplies POS even without optional OS English tagging assets. Native Swift predictions match fixed vectors from original NLTK 3.9.2 classes. Noun lemma candidates require actual dictionary senses, and target plurals require attested forms in SQLite. Unknown and ambiguous forms are skipped.

Sense ranking uses POS, contextual gates for high-risk polysemes, gloss keywords and ambiguity checks. Repeated words use local context; unique words can use their sentence. Hyphenated compounds are not partly translated. Subject forms are not substituted for object/reflexive pronouns merely because their lemmas match.

Per-language frequency refers to source word tokens. Combined requests above 50% are proportionally scaled. Seeded selection first spreads words, then at high density permits pairs but never three consecutive replacements. No overlaps, destructive source changes or translation chaining occur. Actual density can be below the target and remains a diagnostic in the session reading.

Readings and replacement spans now live only in a non-Codable ReadingSession. Backgrounding unloads inference but preserves that value; process termination discards it, and the next launch starts empty. Remix updates the same in-memory original. Database migration v2 drops the legacy reading/replacement tables while preserving vocabulary, lists, settings, card due dates and review logs. Saving a word keeps only its original/mixed example sentence, independently of the reading session. Refresh revisions prevent stale async vocabulary/settings updates.

Inference verifies the selected 532,517,120-byte GGUF before native loading. Each generation owns and releases context/sampler resources; model reuse/unload are serialized. The Qwen3.5 chat template supplies an empty thinking block. Bounded structural validation/retry cannot certify semantics or CEFR.

SRS tables retain card state, history and scheduler version. Validated FSRS6 review sessions remain future work. Case, agreement, full verbs/adjectives and multiword replacement are also open; displayed mixed text is an English frame with lexical insertions.

GenerationVocabularyPlanner selects up to three English noun hints per enabled language from topic pools, verifying that each hint has a real local dictionary equivalent that passes LexicalContrastPolicy. The prompt names the enabled languages but contains only English vocabulary, never target translations or earlier passages. International terms may occur naturally in the original prose.

LexicalContrastPolicy runs before allocation on both the resolved lemma and rendered form. Unicode folding, transliteration, spelling/suffix normalization and edit distance exclude identical and near-identical pairs across scripts. This is a conservative lookalike heuristic, not verified etymology: existing WikDict packs contain no reliable word-origin field, and some loans/cognates can escape or distinct pairs be skipped. Final sense/morphology validation still applies; density is never forced to compensate.

Every inference attempt creates and frees its own llama context and sampler; only model weights are reused. A process-local planner rotates through 576 situation/focus/perspective combinations, avoiding repeated base situations until all 12 have been used. Normalized text, opening, phrase-overlap and content-word checks reject duplicate/near-duplicate output with the existing two-attempt limit. Fingerprints are used only for post-inference validation, never as a conversation transcript. This reduces repetition but cannot prove semantic uniqueness or CEFR quality.

WritingGenre supplies six literary prompts. Dialogue, play and poem use native llama.cpp grammar sampling to enforce speaker-turn/line structure while the model generates the content. Poems have genre-specific minimum length and line-aware vocabulary context. Literary quality is still model-dependent.

ReplacementMode.focused restricts candidates to any combination of structure/content/actions. It selects every safe candidate without the balanced mode's density/adjacency caps, allocating languages by relative positive weights and rebalancing over available choices. Balanced behavior remains unchanged. Eligible/actual counts are shown separately. Bundled Penn tags and conservative English lemma/agreement analysis select attested practiceForm rows; unsupported grammar remains English.

SentenceSpeechController retains AVSpeechSynthesizer and queues the selected sentence as language-tagged utterances, or as one original-English utterance. It enumerates on-device voices, excludes novelty voices, reports missing languages and initiates no downloads. Stop, sheet dismissal and backgrounding stop audio; reading-session lifetime remains unchanged. The pure speech plan preserves UTF-16 boundaries and reads only the selected line for poems. Apple API: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer .
