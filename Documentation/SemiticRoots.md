# Semitic Roots integration

## Integration plan

The real application has one `LinguaFrancaCore` Swift package, `LinguaFrancaInference`,
SwiftUI feature folders and GRDB. `ContextualReplacementEngine` and `LanguagePack`
are the existing replacement engine/adapter interfaces; no `PolyglotEngine` exists.

1. Add source-pinned, preprocessed Arabic/Hebrew/Classical Syriac SQLite packs using
   the existing manifest and bootstrap conventions. Keep dictionaries read-only;
   add root/lexeme/form/provenance tables to these same language packs.
2. Add a paginated root catalog, details and attested-form Morphology Lab as a fifth
   tab. Save selections into the existing vocabulary/deck tables. Add an optional
   lexical-reference table in a non-destructive migration; preserve all old cards
   and review history. SRS was deferred during the initial Semitic integration; the subsequent user request adds FSRS 6 and flashcards (see Aggressive2BAndSRS.md).
3. Extend existing vocabulary practice requests/results with lexical constraints,
   occurrence annotations, used/omitted selection IDs and validation status. Keep
   generated readings in process memory, as before.
4. Arabic/Hebrew use the existing Qwen runtime with verified candidate forms. Syriac
   uses a seeded corpus-grounded backend in the same application workflow, without
   asking Qwen to produce Syriac. Unsupported constraints are reported explicitly.
5. Extend the existing SQLite adapter with attested Semitic morphology; preserve
   English source spans and the German/Russian path. Add RTL rendering, combining-
   mark-safe annotations and voice availability checks.
6. Run data, migration, Unicode, old-feature regression, actual model and build
   checks. Record measured coverage and unsupported linguistic cases honestly.

## Scope and licensing decisions

The selected user varieties are Modern Standard Arabic, Modern Hebrew and Classical
Syriac. Biblical Hebrew data is not used as a substitute for Modern Hebrew paradigms.
ETCBC's main Syriac corpus is CC BY-NC 4.0 and is bundled with the user's explicit authorization for personal/noncommercial use. It is pinned to ded39ecaa145d3a6b0ec83fe24d0e00699cddb19. Kaikki/Wiktionary data supplies additional licensed lexical records. Existing cards/history survive the additive migrations. Native Syriac passages use original corpus frames; Aggressive mixed passages select Syriac expressions only from attested corpus entries, retaining their lexical references. No unrestricted Syriac LLM prose is used.
