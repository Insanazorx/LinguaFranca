# LinguaFranca

Native Swift 6 / SwiftUI iOS app that generates English passages locally with Qwen3.5-0.8B, then mixes German and Russian vocabulary using independent frequency controls. Models, dictionaries and native dependencies are restored during the build; they are not stored in Git.

## Build from a fresh clone

Use macOS with full Xcode (Swift 6.1 or newer), its iOS and simulator SDKs, and Python 3.9+. Open Xcode once to complete Apple's installation steps. CMake 3.28+ is required for the simulator runtime; the script installs it with Homebrew if missing. Without Homebrew, install CMake before running the build.

```sh
git clone https://github.com/Insanazorx/LinguaFranca.git
cd LinguaFranca
./build.sh --test
```

This command downloads checksum-pinned dependencies, compiles the missing llama.cpp simulator slice, prepares the lexical databases and English analysis model, retrieves the selected Qwen GGUF, generates the Xcode project, runs tests, builds the simulator app, and checks the resources in the actual app bundle. Output: `build/DerivedData/Build/Products/Debug-iphonesimulator/LinguaFranca.app`. Logs and verified downloads are in `.bootstrap/`.

```sh
# Restore everything, then open the generated project in Xcode.
./build.sh --bootstrap-only
open LinguaFranca.xcodeproj

# Build for an iPhone without signing.
./build.sh --platform device

# Sign with your own Xcode account/team.
./build.sh --platform device --team-id YOUR_TEAM_ID

# Reuse the already downloaded, verified cache without network access.
./build.sh --test --offline
```

Signing and installation on a phone require your own Apple account/team and device approval. No signing credentials or personal Xcode state are committed. The app runs the model and language processing on the device; it never downloads resources at runtime.

## GitHub build

In the repository's **Actions → Build iOS app → Run workflow** screen, start the included macOS build. It restores dependencies, runs the same tests, builds the simulator app and verifies bundled offline resources. It needs no Apple signing secrets. It is manual and does not run automatically on every push. A remote workflow result is separate from the recorded local build results.

## Reading and vocabulary

Every registered target language has a saved frequency slider from zero to Psycho (50% target). Simultaneous languages share an overall 50% ceiling. Actual density depends on conservative lexical coverage and is displayed separately. Tap Remix to apply settings to an existing English passage without rerunning the model. Tap a highlighted word to reveal the English original and save it to a list.

Local-model generation, mixed-language reading, vocabulary/list persistence and initial iPhone 13 installation/launch are verified. CEFR is a prompt target; prose and lexical sense selection still need quality review. Full target-language grammar and validated FSRS 6 review scheduling remain open. Mac/simulator timings are not physical-device performance measurements.

See [build details](Documentation/Build.md), [project status](Documentation/Status.md), [verification](Documentation/Verification.md), [model measurements](Documentation/ModelBenchmark.md) and [data licenses](Documentation/LexicalDataLicenses.md).
