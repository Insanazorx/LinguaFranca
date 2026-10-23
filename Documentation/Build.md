# Reproducible source-only build

The repository contains application/library/test source, preparation scripts, source manifests, lock data, licenses and documentation. Generated Xcode projects, Vendor, GGUF weights, derived SQLite dictionaries, English POS model weights, caches, signed apps and local signing state are ignored. Existing local binaries are not deleted when Git is initialized.

## Entry points

`./build.sh --test` performs the complete simulator build. `./build.sh --bootstrap-only` restores dependencies and generates the Xcode project without compiling the app. `--platform device` selects iOS; `--team-id` or `LINGUAFRANCA_TEAM_ID` enables automatic development signing with an account already configured in Xcode. A device build without a team is unsigned. The generator preserves a previous local team selection; generated projects never enter Git.

`--configuration Release` selects an optimized app build. `--cache-dir /path/to/cache` relocates downloads, receipts, dependency build work and logs. `--offline` forbids downloads and tool installation: all required archives must already be in that cache. This is a development option; installed iOS apps always use bundled resources.

Prerequisites are macOS, full Xcode with iOS and simulator SDKs, Python 3.9+, and CMake 3.28+. If CMake is absent and Homebrew is installed, bootstrap installs CMake automatically. Apple account creation, Xcode licenses, credentials and device approvals remain interactive user steps. The build never installs Xcode or handles account passwords.

## Dependencies restored

| Dependency | Pin / source | Preparation |
|---|---|---|
| GRDB.swift | 7.11.1, exact commit and archive SHA-256 | Restore local Swift package under Vendor |
| llama.cpp | b11829, verified official XCFramework and source archive | Keep official iOS/macOS slices, compile iOS simulator with the unmodified pinned upstream script, merge all three slices |
| Qwen3.5-0.8B Q4_K_M | Exact Unsloth revision, 532,517,120 bytes, SHA-256 | Copy into Resources/Models after verification |
| WikDict English–German/Russian | June 2026 exports, fixed URLs and SHA-256 | Normalize/filter/index into app SQLite packs |
| German noun forms | german-nouns 1.2.5, pinned wheel | Import attested noun plurals from source CSV |
| Russian noun forms | pymorphy3-dicts-ru 2.4.417150.4580142, pinned wheel | Import attested noun plurals using pinned build-only Python readers |
| Morphology readers | pymorphy3 2.0.6 and dawg2-python 0.9.0, pinned wheels | Extract modules into temporary build work; no Python in the app |
| English POS model | NLTK averaged perceptron, archive and individual file hashes | Restore unchanged JSON consumed by native Swift |

The canonical pins are Documentation/Dependencies.lock.json, Resources/Models/model-manifest.json and Resources/LanguagePacks/_english/model-manifest.json. PyPI lookup uses a fixed package version and exact wheel filename/digest; it never resolves a latest version. Toolchain versions are printed/recorded by Xcode and CI. A first uncached run downloads roughly 700 MB before optional CMake installation and requires additional local space for native compilation and build outputs.

## Integrity and reuse

Downloads use HTTPS, bounded retries, resumable partial files and SHA-256 validation before publication. A corrupt download is never installed. Framework symlinks are preserved and archive traversal is rejected. Generated dependency directories are replaced transactionally. Receipts verify output hashes and preparation-script fingerprints before reuse. A cache lock prevents concurrent bootstrap writers. Dictionary manifests are regenerated alongside derived databases, so their hashes describe the actual packaged bytes even if SQLite versions change their physical layout.

The bundle verifier checks the executable's framework search path, embedded llama framework, exactly one selected model and its hash, both SQLite packs and their integrity/hashes, offline English POS files/hashes, and bundled license notices. Build/test commands fail immediately on errors and preserve diagnostic logs.

## GitHub Actions

`.github/workflows/build.yml` is manually dispatched on a macOS runner. Official checkout/cache actions are pinned by commit SHA. Cache keys include the runner architecture, Xcode version and dependency/preparation inputs. No Apple certificates, provisioning profiles or signing secrets are required. The workflow does not publish an App Store build or install onto personal phones.

## Licenses and limits

Full attribution and Apache/MIT/CC BY-SA texts remain in Resources. Source URLs, exact revisions, hashes and transformations are documented. Bootstrap downloads happen only on the development/build machine; the iOS target adds no networking or cloud inference.

Recorded acceptance results for this implementation are in Verification.md. Remote GitHub Actions success must be checked independently; a local build is not a remote CI result.
