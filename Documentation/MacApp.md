# Native macOS application

LinguaFranca now has a native macOS 14+ SwiftUI/AppKit target, `LinguaFrancaMac`, with the **LinguaFranca Mac** scheme. The executable uses `LC_BUILD_VERSION platform MACOS`; Mac Catalyst is disabled. The iOS targets retain their existing bundle identities and deployment settings. Per the user's instruction, Mac presentation sources live exclusively under `Mac/` and are not iOS compile inputs. The Core and Inference packages and bundled data are shared; iOS presentation APIs and interactions are preserved.

## Implementation

- `Mac/App/MacNavigationView.swift`: five-section native sidebar, shared selection, and termination after closing the last window. `Mac/App/LinguaFrancaApp.swift` supplies a resizable main window, macOS Settings, Cmd–1…5 navigation, adaptive dark-mode tint, and platform-specific application lifecycle handling.
- `Mac/UIComponents/PlatformSupport.swift`: iOS inline titles/presentation detents and macOS sheet sizes/grouped scrolling forms. Mac-specific feature views retain generation, study, vocabulary, dictionaries and Semitic tools independently of the iOS UI.
- `Mac/App/AppEnvironment.swift`: platform-appropriate library directory attributes. No database schema or scheduler change is needed. Generation services, language packs, dictionary queries and persistence stay shared. The Mac application delegate waits for cancellation and model unload before allowing termination, so Metal resources are released before native global destructors run.
- `Mac/Features/Study/StudyView.swift`: the same two-dimensional drag and flip gestures, plus Space to flip, Left/Right to review and Escape to close. Vocabulary/list context menus provide mouse access to edit, rename and removal actions.
- `Mac/UIComponents/SentenceSpeechController.swift`: native word-only AVSpeechSynthesizer, without iOS audio-session calls. No substitute Syriac voice or sentence playback was added.
- `Tools/mac_bootstrap.py`, `Tools/build.py`, `Tools/generate_project.py`, `Tools/verify_app_bundle.py`: native framework bootstrap, separate Mac target/signing settings, bundle layout validation, native Mach-O platform check, checksums and signature verification. `Tools/prepare_mac_icon.swift` draws the original app icon using AppKit; the generated `.icns` remains outside Git.
- `Resources/Mac/LinguaFranca.entitlements`: App Sandbox, without network entitlements. The models, five language packs, dictionary index, English analysis data, Syriac font and license notices ship in the Mac bundle.

Both models remain exclusive to their existing modes: Qwen3.5-0.8B for Balanced and Qwen3.5-2B for Aggressive. The application does not fetch assets at runtime. Switching focus to another Mac app does not cancel generation. Quitting clears process-only readings and keeps vocabulary, lists, settings and review history.

## Build and installation

```sh
./build.sh --platform mac --configuration Release --team-id YOUR_APPLE_TEAM_ID --test
# With a complete verified local cache:
./build.sh --platform mac --configuration Release --team-id YOUR_APPLE_TEAM_ID --offline
```

Output: `build/DerivedData/Build/Products/Release/LinguaFranca.app`. Full Xcode with the macOS SDK is required. Native Mac bootstrap reuses the pinned official llama.cpp macOS framework slice and does not compile the iOS simulator runtime. It retains the shared dependency/data preparation pipeline.

The installed Release artifact and its embedded llama framework are signed with the same existing Apple Development team. App Sandbox and Hardened Runtime library validation remain enabled, without network entitlements or library-validation exceptions. Debug development builds can use ad-hoc signing; hardened Release requires `--team-id` and a matching Apple signing identity. This is a personal local installation, not an App Store or notarized distribution. It has a separate local library from the iOS app. For this installation, a consistent SQLite backup copied the existing simulator library once into the previously absent Mac library: one word, one list, one card, three review logs. The source was opened read-only and no existing Mac library was overwritten. This does not create ongoing synchronization.

## Validation on 24 October 2026

- Native Debug and Apple-signed Release builds on this Apple Silicon Mac; `vtool` confirms `MACOS`, not Catalyst. Both bundled models and all five language packs pass checksum/integrity checks. The final bundle passes deep/strict code-signature verification.
- Swift package suite: 88 core tests and 4 inference tests passed. Build/data preparation suite: 17 tests passed, including a generated-project test proving that Mac and iOS sources have separate target membership. These include existing FSRS reference vectors, persistence, replacement, Semitic and dictionary coverage tests.
- Native UI with a separate seeded test library: leftward diagonal mouse drag records Again, Right key records Good, Space flips the card, the completion screen appears, and the Forgotten list increases. After quit/relaunch the three saved words and one forgotten word remain, while the generated-reading list is empty.
- Native dictionary UI: English `bank` finds distinct German/Russian/Arabic/Hebrew/Syriac entries. Native Syriac `ܐܝܕܐ` finds senses; entry details display meaning, etymology, recorded forms and source information.
- Actual app generation: Balanced displayed a mixed passage and its tappable word sheet; a word was saved and the native pronunciation control entered its speaking state. Aggressive displayed a paired passage with 50/50 selected occurrences mapped. These are functional checks, not a guarantee that the model's translations or grammar are correct.

The installed Apple-signed Release opens successfully and displays the native word sheet with grouped, scrolling form content. A prior iOS simulator build also passed; no iOS app was installed or updated during this port. The final Mac-only termination cleanup has not yet been exercised by quitting the current user reading.

No Intel Mac, physical-iPhone performance, App Store distribution or notarization validation was performed as part of this desktop port. Model linguistic limitations remain documented in `Aggressive2BAndSRS.md`; this port does not improve or retrain the models. The next practical step is personal use of the installed native Mac app.

## Finder/Dock icon registration — 28 October 2026

The .icns resource was present and valid, but built Mac Info.plist files omitted CFBundleIconFile despite the previous generated-plist build setting. That left Finder and the running application without a declared icon. Resources/Mac/Info.plist now explicitly declares LinguaFranca.icns and the ordinary native Mac bundle fields. Only the Mac target consumes this template with GENERATE_INFOPLIST_FILE=NO; iOS keeps its generated plist and AppIcon asset catalog. The template is a build input, not a copied resource.

Tools/verify_app_bundle.py now rejects a Mac artifact without the icon declaration or a valid ICNS container. Tests/BuildTests/test_mac_target.py checks both Mac configurations, icon resource membership, exclusion of the metadata template from copied resources, and unchanged iOS icon/plist settings. All 23 build/data tests passed. The signed Mac Release built, passed full offline-resource checks and strict signature validation, and replaced /Applications/LinguaFranca.app with a recoverable previous bundle. Its Launch Services registration alone was refreshed; global icon caches and Dock preferences were not reset.

Native Finder inspection showed the green book instead of the blank icon. NSRunningApplication.icon for the installed, launched Mac app resolved to the expected 1024×1024 green book. Direct Dock accessibility capture was unavailable; no separate Dock screenshot is claimed. Existing normal Mac library opened with its saved reading and preferences. iPhone app installation, models, application data and iOS sources were not changed by this Mac-only fix. No inference/SRS retest was necessary for bundle metadata.
