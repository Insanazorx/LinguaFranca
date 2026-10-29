import SwiftUI
import LinguaFrancaCore

struct GenerationOptionsView: View {
    @Environment(AppEnvironment.self) private var model
    @Binding var settings: AppSettings
    @State private var languagesExpanded = false
    private var languagesTitle: String {
        settings.enabledLanguages.isEmpty ? "Choose languages" : settings.enabledLanguages.map(Theme.language).joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Reading level", selection: $settings.generationLevel) {
                ForEach(CEFRLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("reading-level")
            if settings.generationLevel == .nichijou {
                Text("Everyday language · common words, useful expressions and natural conversation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Topic", selection: $settings.generationTopic) {
                ForEach(model.availableTopics, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
            DisclosureGroup(isExpanded: $languagesExpanded) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(model.languagePacks, id: \.languageCode) { pack in
                        languageOptions(code: pack.languageCode, name: pack.displayName)
                    }
                    if settings.replacementMode == .balanced {
                        Text("Combined target: \(Int((settings.effectiveFrequencies.values.reduce(0, +) * 100).rounded()))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target languages").font(.subheadline.weight(.semibold))
                    Text(languagesTitle).font(.caption).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("generation-languages")
            Divider()
            ReadingOptionsView(settings: $settings)
        }
    }
    private func languageOptions(code: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(name, isOn: Binding(get: { settings.enabledLanguages.contains(code) }, set: { enabled in
                if enabled {
                    if !settings.enabledLanguages.contains(code) { settings.enabledLanguages.append(code) }
                    if settings.languageWeights[code] == nil { settings.languageWeights[code] = 0.5 }
                    if settings.languageFrequencies[code] == nil { settings.languageFrequencies[code] = 0.1 }
                } else { settings.enabledLanguages.removeAll { $0 == code } }
            }))
            if settings.enabledLanguages.contains(code), settings.replacementMode == .balanced {
                HStack {
                    Text("Frequency").font(.caption)
                    Spacer()
                    Text(settings.frequency(for: code) >= 0.495 ? "Psycho · 50%" : "\(Int((settings.frequency(for: code) * 100).rounded()))%")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.forest)
                }
                Slider(value: Binding(get: { settings.frequency(for: code) }, set: { value in
                    // One atomic binding write preserves all other recent choices.
                    var next = settings
                    for language in next.enabledLanguages where next.languageFrequencies[language] == nil {
                        next.languageFrequencies[language] = next.frequency(for: language)
                    }
                    next.languageFrequencies[code] = value
                    settings = next
                }), in: 0...0.5, step: 0.01).accessibilityLabel("\(name) frequency")
                if settings.frequency(for: code) != settings.effectiveFrequencies[code] {
                    Text("Combined share: \(Int(((settings.effectiveFrequencies[code] ?? 0) * 100).rounded()))% of words")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
