# Semitic comparisons and catalog practice — 2 November 2026

Semitic Roots now opens a comparison catalog rather than three unrelated root lists.
Its default view includes every pair or triple found by the documented rules in the
bundled packs: 906 families, 2,050 root records, 685 two-language families and 221
three-language families. Pair filters overlap: Arabic–Hebrew 650, Arabic–Syriac 265,
Hebrew–Syriac 433. The previous all-roots inventory, saving, word details, examples
and Morphology Lab remain accessible.

## Evidence and usage

The reproducible builder joins exact consonant identifiers without merging emphatic
and plain consonants, adds shared source-recorded ancestral links, and applies six
reviewed comparison notes. It labels 840 matching-consonant comparisons, 60 recorded
historical comparisons and six reviewed comparisons separately. Identical consonants
are an invitation to compare, not a proof of cognacy or semantic equivalence.
English meanings never establish family membership. Homographs and independent senses
remain visible; a common historical ancestor does not make every derivative synonymous.

The six reviewed families are k-t-b, ʿ-b-d, s-p-r/s-f-r, ṣ-l-ḥ, k-l-b and sh-l-m/s-l-m.
Notes explain semantic differences, ordinary book vocabulary crossing k-t-b/s-p-r,
and the distinction between Arabic worship/service, Hebrew work and Syriac do/make.
Reviewed exact headword/POS/sense links repair missing root associations for already
attested words. They never generate new words, pronunciations or paradigms, and do
not attach same-spelling but differently vocalized homographs indiscriminately.
A reviewed uncertain ant→dog-root association is detached without deleting the ant
word or any dictionary forms. Broad upstream header-maintenance categories must not
be used to reject words: they also label valid records throughout the source dump.

Each detail shows all three language sections, word meanings, source transliterations,
stems/patterns where supplied, referenced examples, full inventory links and comparison
sources. Missing third-language data is labelled as missing coverage, not absence.
The first twelve ranked word records are previews; full inventories remain accessible.

Modern usage is reviewed for those six families, not certified for all 906. Elsewhere
the UI explicitly says that contemporary spoken frequency/register or survival has
not been independently verified. Arabic data is standard Arabic rather than a universal
spoken dialect. Classical Syriac remains the installed variety; cited Assyrian
Neo-Aramaic or Turoyo continuations are named separately, never presented as Classical
conjugations. A root may survive with changed meanings or in particular registers.

Sources are the existing pinned Kaikki/Wiktionary CC BY-SA 4.0 packs and the user-authorized
ETCBC Classical Syriac corpus (CC BY-NC 4.0). Original learning notes and source links
are in `Tools/Data/semitic_learning.json`; the build fingerprint includes that file.
Reference entries include [Hebrew work](https://en.wiktionary.org/wiki/עבד),
[Modern Assyrian do/make](https://en.wiktionary.org/wiki/ܥܒܕ),
[book/writing](https://en.wiktionary.org/wiki/ܟܬܒܐ),
[Hebrew ספר](https://en.wiktionary.org/wiki/ספר), and
[Syriac/Neo-Aramaic dog](https://en.wiktionary.org/wiki/ܟܠܒܐ).
No SEDRA database or additional model was downloaded or redistributed.

Separator-insensitive search accepts `k l b`, `K-L-B`, native letters and meanings.
ASCII aliases also fold scholarly transliteration for search; those lossy aliases
never determine family identity. Latin Vocab also gains an explicit three-language filter.

## Practice

Both catalogs offer Shuffle & practice, using their current query, language combination
and (for Latin) word type. A mini-set samples 8, 12 or 20 families, admits eligible due
families, and samples real dictionary lexemes across the chosen languages. The actual
previously reviewed due sense replaces a new random sense when revisiting its family.
Sampling is reproducible with a seed. Only identifiers and the selected word records
are read; full dictionaries are not loaded into memory.

The portrait cards have colored backing cards and a two-dimensional drag interaction.
Tap to reveal, swipe right for Good or left for Again. Rating requires revealing first.
Backs show independent meanings, source forms/transliterations, family peers and a
dictionary button that returns to the same card. The selection continues until Exit.
The session header shows recall points, current combo, best combo and answer count;
catalog statistics retain total points, answers, best combo and best session.

Eligible sets include a family with a supported context sense when one exists in the
current filters. Twenty-one authored English noun scaffolds provide contextual clues;
only the target word is non-English. Exact dictionary senses select these scaffolds.
Verbs and ambiguous unsupported concepts do not receive invented contextual inflections.
Semitic cards always ask a source-attested lexical word or pattern realization, never
a hyphenated consonant puzzle. Citation forms can be the tested word; complete target-
language sentence grammar is not claimed. Context-capable cards alternate with bare-word
presentation over successive passes through the selection. Card scroll position resets
when the face or word changes.

Recall is explicitly self-rated rather than automatically graded. A recalled answer
earns 10 points plus a capped combo bonus; context adds 5. Again earns no points and
resets the current combo. These practice points are not a measured proficiency score.

Migration `v6_catalog_practice` adds separate catalog cards, rounds, memberships and
immutable review events. Scheduling uses the already reference-tested FSRS 6 implementation,
with real timestamps, Good/Again ratings and no fabricated intervals. Card, score and
review event writes are one transaction, stale answers are rejected and repeated event
IDs are idempotent. Saved vocabulary, decks, ordinary SRS cards and histories are untouched.
Scores survive process termination because every accepted answer is stored immediately.
No inference model, speech model, remote request, account or runtime download is involved.

## Validation

133 Swift tests passed (124 Core, 9 inference), including new source-backed search,
pair/triple eligibility, reproducible sampling, context availability, actual word forms,
FSRS equality, score/combo behavior, persistence, stale/duplicate answers, session membership
and continuous queue tests. All 28 Python tests passed, including reproducibility, strict identity,
reviewed homograph handling and conservative correction of uncertain associations without vocabulary loss. Signed native Mac
and iOS Release builds include strict signature and full offline asset checksum checks.

Native Mac interaction used a separately identified temporary signed application and a
separate empty library, preserving the normal user library. Verified `k l b` search,
three-language dog comparison, Syriac-in-English context, reveal, word→dictionary→same
card return, actual right/left drags, 0→15→25 points, 1×→2×→0× combo, continued cards after
covering the selected set, and persisted exit statistics. Latin random practice produced
19 words from eight families and recorded an independent 10-point review.

The phone installation and final library-preservation results are recorded in Status.md.
No new LLM quality, thermal/battery, fresh-airplane-mode installation or long-running
physical-device stress measurements are claimed for this catalog-only milestone.

## Main implementation files

- `Tools/prepare_semitic_families.py`, `Tools/Data/semitic_learning.json` and the
  existing Semitic builder/bootstrap prepare the versioned comparison database.
- `Core/Semitic/SemiticFamilies.swift` and `SemiticLexicon.swift` implement indexed
  comparison lookup, root aliases and attested word access.
- `Core/CatalogPractice/` contains deterministic mini-set sampling, authored context
  selection, questions, scoring and continuous selection logic.
- `Core/Persistence/CatalogPracticeRepository.swift` and the additive migration in
  `DatabaseManager.swift` persist FSRS snapshots, rounds and review events.
- Both platforms' `SemiticFamilyView.swift`, `SemiticRootsView.swift`,
  `LatinVocabularyView.swift` and `CatalogPracticeView.swift` connect browsing and play.
- `Tests/CoreTests/CatalogPracticeTests.swift`, the migration expectation, Semitic
  builder/family tests and `Tools/verify_app_bundle.py` cover regressions and packaging.
