import SwiftUI
import LinguaFrancaCore

struct InteractivePassageView: View {
    let passage: GeneratedText
    @State private var selected: ReplacementSpan?
    var body: some View {
        Text(attributed).font(.system(.body, design: .serif)).lineSpacing(7)
            .tint(Theme.forest)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "linguafranca", url.host == "word",
                      let span = passage.replacements.first(where: { $0.id == url.lastPathComponent }) else { return .discarded }
                selected = span
                return .handled
            })
            .sheet(item: $selected) { span in
                PassageWordSheet(passage: passage, span: span)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
    }
    private var attributed: AttributedString {
        do {
            _ = try passage.renderedText()
            var text = AttributedString(), cursor = passage.originalEnglish.startIndex
            for span in passage.replacements.sorted(by: { $0.originalUTF16Range.location < $1.originalUTF16Range.location }) {
                let range = try span.originalUTF16Range.range(in: passage.originalEnglish)
                text += AttributedString(String(passage.originalEnglish[cursor..<range.lowerBound]))
                var word = AttributedString(span.targetSurface)
                word.link = URL(string: "linguafranca://word/" + span.id)
                let color = span.targetLanguageCode == "de" ? Theme.german : Theme.russian
                word.foregroundColor = color
                word.backgroundColor = color.opacity(0.08)
                word.underlineStyle = .single
                text += word
                cursor = range.upperBound
            }
            text += AttributedString(String(passage.originalEnglish[cursor...]))
            return text
        } catch { return AttributedString(passage.originalEnglish) }
    }
}

struct PassageWordSheet: View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    let passage: GeneratedText
    let span: ReplacementSpan
    @State private var deck = ""
    @State private var name = ""
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Theme.language(span.targetLanguageCode).uppercased()).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Text(span.targetSurface).font(.system(.largeTitle, design: .serif)).foregroundStyle(span.targetLanguageCode == "de" ? Theme.german : Theme.russian)
                        Text(span.originalSurface).font(.title3)
                        Text(span.senseDescription?.isEmpty == false ? span.senseDescription! : span.originalPartOfSpeech.capitalized)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }
                Section("Save to your vocabulary") {
                    Picker("List", selection: $deck) {
                        ForEach(model.decks) { Text($0.name).tag($0.id) }
                        Text("Create a new list…").tag("new")
                    }.disabled(saved)
                    if deck == "new" { TextField("List name", text: $name).disabled(saved) }
                    Button {
                        Task { await save() }
                    } label: {
                        Label(saved ? "Saved to vocabulary" : "Save word", systemImage: saved ? "checkmark.circle.fill" : "bookmark")
                            .frame(maxWidth: .infinity)
                    }.disabled(saving || saved || (deck == "new" && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section("In context") { Text(passage.originalEnglish).font(.system(.body, design: .serif)).lineSpacing(4) }
            }.navigationTitle("A word to keep").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { deck = model.decks.first?.id ?? "new" }
        }
    }
    private func save() async {
        guard let database = model.database else { return }
        saving = true
        defer { saving = false }
        do {
            let draft = try VocabularyDraft(englishLemma: span.originalLemma, targetLanguage: span.targetLanguageCode,
                targetLemma: span.targetLemma, targetSurface: span.targetSurface, senseID: span.sourceSenseID,
                partOfSpeech: span.originalPartOfSpeech, exampleEnglish: passage.originalEnglish,
                exampleMixed: passage.renderedText()).validated()
            let id: String
            if deck == "new" { id = try await database.createDeck(name: name) } else { id = deck }
            _ = try await database.saveVocabulary(draft, inDeck: id)
            try await model.refresh()
            saved = true
        } catch { self.error = error.localizedDescription }
    }
}
