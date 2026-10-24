import SwiftUI
import LinguaFrancaCore

struct ReadingOptionsView: View {
    @Binding var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Writing", selection: $settings.writingGenre) {
                ForEach(WritingGenre.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("writing-genre")
            Picker("Practice mode", selection: $settings.replacementMode) {
                Text("Balanced").tag(ReplacementMode.balanced)
                Text("Aggressive").tag(ReplacementMode.aggressive)
            }.pickerStyle(.segmented)
            if settings.replacementMode == .aggressive {
                ForEach(PracticeDomain.allCases) { domain in
                    Toggle(isOn: Binding(get: { settings.practiceDomains.contains(domain) }, set: { enabled in
                        if enabled { settings.practiceDomains.insert(domain) } else { settings.practiceDomains.remove(domain) }
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(domain.title).font(.subheadline.weight(.medium))
                            Text(domain.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("domain-" + domain.rawValue)
                }
                Text(settings.practiceDomains.isEmpty ? "Select at least one group to mix words." : "Generate an extremely dense concentration of the selected features, then translate every selected component without frequency or spacing limits. All selected profiles combine. A reading is complete only after every selected component is verified; the English draft remains available throughout. Use Remix for an existing reading.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
