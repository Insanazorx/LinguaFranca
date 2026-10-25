# Continuous card study

Study now stays open until the user selects the card's exit control. There is no end-of-list screen, progress counter, separate rating panel or daily/due-date gate. Cards are portrait rectangles at 2:3, with randomly chosen yellow, green, blue and red backgrounds; consecutive presentations use different colors. Colors carry no learning-state meaning.

Tap to turn a card. Drag it freely in two dimensions; right rates Good and left rates Again. Short/vertical releases spring back. The back retains the English meaning, language, part of speech, dictionary definition and contextual example. A card context menu provides all four FSRS ratings without permanent on-screen buttons. Keyboard controls remain Space to flip, arrows to rate, 1–4 for Again/Hard/Good/Easy and Escape to exit.

iOS presents this as a full-screen cover, hiding app navigation and system overlays. Mac replaces the main content with the card canvas and restores the study section on exit, retaining its selected list. The two targets keep their separate presentation sources.

## Scheduling and persistence

`Core/SRS/ContinuousStudySession.swift` holds only the chosen cards. Due learning/relearning steps come first, followed by due mature reviews. When nothing is due, early practice balances exposure across the selection and uses real FSRS due dates as a tie breaker. The previous card is avoided when another card exists; a one-word selection repeats indefinitely. Previously forgotten words remain in the current selection after they become familiar. New words outside that selection are never admitted automatically.

The existing validated FSRS 6 equations, retention preference, learning steps and durable review events remain in use. This is continuous voluntary practice with early reviews; it does not pretend that future due dates have arrived or impose a conventional Anki session-completion gate. No migration is required.

`Core/Persistence/StudyRepository.swift` now reads back each saved card before returning it and recording its JSON snapshot. SQLite's Unix-epoch Double can round a Foundation Date by a fraction of a microsecond; returning the in-memory pre-save date caused an unchanged repeated card to fail the strict stale-write check. Reading the actual stored representation fixes this while preserving stale-write protection and idempotent event replay.

## Files and checks

- Added the shared continuous queue and `Tests/CoreTests/ContinuousStudyTests.swift`.
- Added `Features/Study/ReviewSessionView.swift` and the separate Mac counterpart; updated both Study screens and Mac root/environment presentation.
- 94 core and 4 inference Swift tests, including FSRS reference cases, passed. The 17 build/data preparation tests passed. Native Mac Release and iOS simulator builds, offline resource checks and Mac signing verification passed.
- New tests cover due-card priority, 200 uninterrupted reviews with fresh snapshots, a one-card selection, empty/duplicate selections, external deletion/reconciliation, durable repeated writes, fractional-second timestamps and idempotent replay.

Native UI checks: Mac showed only the portrait card, Space flipped it and Escape returned to Study. In an isolated iOS simulator library, vertical dragging sprang back, tapping revealed the back, and eight consecutive left/right swipes cycled the same two words without completion or stale-write errors. Database read-back confirmed all eight new reviews persisted. The X control exited to Study; the simulator was then restored to the normal user library.

Physical iPhone 13 touch/performance validation is not included; the available simulator is iPhone Duo. Existing word lists, internal progress states and review histories are preserved. The next step is personal practice with the updated cards.
