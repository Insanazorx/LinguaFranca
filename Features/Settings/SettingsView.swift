import SwiftUI
import LinguaFrancaCore

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var model
    @State private var draft = AppSettings()
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Reading preferences") {
                    ReadingOptionsView(settings: $draft)
                    Picker("English level", selection: $draft.generationLevel) {
                        ForEach(CEFRLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Stepper("About \(draft.defaultWordCount) words", value: $draft.defaultWordCount, in: 90...150, step: 10)
                }
                Section {
                    ForEach(model.languagePacks, id: \.languageCode) { pack in
                        let code = pack.languageCode
                        VStack(alignment: .leading, spacing: 12) {
                            languageToggle(code, name: pack.displayName)
                            if draft.enabledLanguages.contains(code) && draft.replacementMode == .balanced {
                                HStack {
                                    Text(draft.replacementMode == .aggressive ? "Language weight" : "Frequency")
                                    Spacer()
                                    Text(draft.frequency(for: code) >= 0.495 ? "Psycho · 50%" : "\(Int((draft.frequency(for: code) * 100).rounded()))%")
                                        .fontWeight(.semibold).foregroundStyle(Theme.forest)
                                }.font(.subheadline)
                                Slider(value: Binding(get: { draft.frequency(for: code) }, set: { value in
                                    // Freeze legacy-derived values before changing one language.
                                    for language in draft.enabledLanguages where draft.languageFrequencies[language] == nil {
                                        draft.languageFrequencies[language] = draft.frequency(for: language)
                                    }
                                    draft.languageFrequencies[code] = value
                                }), in: 0...0.5, step: 0.01)
                                    .accessibilityLabel("\(pack.displayName) frequency")
                                    .accessibilityValue("\(Int((draft.frequency(for: code) * 100).rounded())) percent")
                                HStack { Text("Off"); Spacer(); Text("Gentle"); Spacer(); Text("Psycho") }
                                    .font(.caption).foregroundStyle(.secondary)
                                if draft.frequency(for: code) != draft.effectiveFrequencies[code] {
                                    Text("Combined share: \(Int(((draft.effectiveFrequencies[code] ?? 0) * 100).rounded()))% of words")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 5)
                    }
                    if draft.replacementMode == .balanced {
                        LabeledContent("Combined target", value: "\(Int((draft.effectiveFrequencies.values.reduce(0,+) * 100).rounded()))%")
                    }
                } header: { Text("Language practice") } footer: {
                    Text(draft.replacementMode == .aggressive ? "Aggressive uses Qwen3.5-2B and the language assigned to each category. Balanced frequencies have no effect. Coverage is checked automatically; translation meaning and grammar are model-generated. Save, then tap Remix on a reading." : "Psycho targets one word in every 2–3. Each language remembers its frequency; together they share a 50% ceiling. International lookalikes and words without a clear match stay in English, so the actual mix can be lower. Save, then tap Remix on a passage to try it.")
                }
                Section("On your device") {
                    LabeledContent("Saved vocabulary", value: "\(model.vocabulary.count)")
                    LabeledContent("Readings this session", value: "\(model.passageCount)")
                    LabeledContent("Library storage", value: ByteCountFormatter.string(fromByteCount: model.storageBytes, countStyle: .file))
                    LabeledContent("Reading source", value: model.modelDisplayName)
                    LabeledContent("Model included", value: model.modelURL == nil ? "Not yet" : "Yes")
                    NavigationLink("Open-source notices") { NoticesView() }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(saved ? "Preferences saved" : "Save preferences") { Task { await save() } }
                        .disabled(saving || draft == model.settings).frame(maxWidth: .infinity)
                }
            }.navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(saved ? "Saved" : "Save") { Task { await save() } }
                            .disabled(saving || draft == model.settings)
                    }
                }
                .onAppear { draft = model.settings }
                .onChange(of: draft) { _, _ in saved = false }
        }
    }
    private func languageToggle(_ code: String, name: String) -> some View {
        Toggle(name, isOn: Binding(get: { draft.enabledLanguages.contains(code) }, set: { enabled in
            if enabled { if !draft.enabledLanguages.contains(code) { draft.enabledLanguages.append(code) }; if draft.languageWeights[code] == nil { draft.languageWeights[code] = 0.5 }; if draft.languageFrequencies[code] == nil { draft.languageFrequencies[code] = 0.1 } }
            else { draft.enabledLanguages.removeAll { $0 == code } }
        }))
    }
    private func save() async {
        saving = true
        defer { saving = false }
        do { try await model.updateSettings(draft); error = nil; saved = true }
        catch { self.error = error.localizedDescription }
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
