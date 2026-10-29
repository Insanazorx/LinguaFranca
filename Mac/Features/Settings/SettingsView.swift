import SwiftUI
import LinguaFrancaCore

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var model
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Choose your reading options above the text on Generate.", systemImage: "text.book.closed")
                    Text("Changes are saved automatically.").font(.footnote).foregroundStyle(.secondary)
                }
                Section { NavigationLink("Language packs") { LanguagePackLibraryView() } }
                Section("On your device") {
                    LabeledContent("Saved vocabulary", value: "\(model.vocabulary.count)")
                    LabeledContent("Readings this session", value: "\(model.passageCount)")
                    LabeledContent("Library storage", value: ByteCountFormatter.string(fromByteCount: model.storageBytes, countStyle: .file))
                    LabeledContent("Reading source", value: model.modelDisplayName)
                    LabeledContent("Model included", value: model.modelURL == nil ? "Not yet" : "Yes")
                    NavigationLink("Open-source notices") { NoticesView() }
                }
            }.nativeFormStyle().navigationTitle("Settings")
        }
    }
}

struct NoticesView: View {
    var body: some View {
        List {
            Section("GRDB.swift") { Text("Gwendal Roué and contributors · MIT license · v7.11.1") }
            Section("llama.cpp") { Text("The ggml authors · MIT license · b11829") }
            Section("Qwen3.5-0.8B · Balanced") { Text("Qwen Team, Alibaba Cloud · Apache License 2.0. Quantization distributed by Unsloth.") }
            Section("Qwen3.5-2B · Aggressive") { Text("Qwen Team, Alibaba Cloud · Apache License 2.0. Quantization distributed by bartowski.") }
            Section("FSRS 6") { Text("Open Spaced Repetition · MIT. Local Swift scheduler with default FSRS 6 weights.") }
            Section("Offline language packs") { Text("WikDict by Karl Bartel. Wiktionary contributors via DBnary · CC BY-SA 4.0. June 2026 data, normalized and indexed by LinguaFranca. Dictionary data remains under the same license.") }
            Section { Text("Full license texts and pinned dependency details are included with this build.").font(.footnote) }
            if let url = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt"),
               let text = try? String(contentsOf: url, encoding: .utf8) { Section("License texts") { Text(text).font(.caption).textSelection(.enabled) } }
        }.navigationTitle("Open-source notices")
    }
}
