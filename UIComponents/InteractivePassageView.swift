import SwiftUI
import LinguaFrancaCore

struct InteractivePassageView: View {
    let passage: GeneratedText
    var highlightedSourceRange:UTF16Span?=nil
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
                let color = Theme.accent(span.targetLanguageCode)
                if span.targetLanguageCode == "syc" { word.font = .custom("NotoSansSyriac-Regular",size:20,relativeTo:.body) }
                word.foregroundColor = color
                word.backgroundColor = color.opacity(0.08)
                word.underlineStyle = .single
                text += word
                cursor = range.upperBound
            }
            text += AttributedString(String(passage.originalEnglish[cursor...]))
            if let source=highlightedSourceRange,let mapped=try? passage.renderedSpan(for:source),
               let rendered=try? passage.renderedText(),let range=try? mapped.range(in:rendered),
               let lower=AttributedString.Index(range.lowerBound,within:text),let upper=AttributedString.Index(range.upperBound,within:text) {
                text[lower..<upper].backgroundColor = .yellow.opacity(0.22)
            }
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
    @State private var speech = SentenceSpeechController()
    @State private var semiticLexeme: SemiticLexeme?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Theme.language(span.targetLanguageCode).uppercased()).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        SemiticOrLatinVocabularyText(text:span.targetSurface,language:span.targetLanguageCode).foregroundStyle(Theme.accent(span.targetLanguageCode))
                        Text(span.originalSurface).font(.title3)
                        Text(span.senseDescription?.isEmpty == false ? span.senseDescription! : span.originalPartOfSpeech.capitalized)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(speech.isSpeaking ? "Stop pronunciation" : "Pronounce", systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill") {
                            if speech.isSpeaking { speech.stop() }
                            else { speech.speak([span.pronunciation]) }
                        }.buttonStyle(.bordered).font(.subheadline)
                            .disabled(!SentenceSpeechController.hasLocalVoice(span.targetLanguageCode))
                            .accessibilityIdentifier("pronounce-word")
                        if let semiticLexeme { NavigationLink("Lexeme, root and morphology") { SemiticLexemeDetailView(lexeme:semiticLexeme) } }
                        if let message = speech.errorMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
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
                .task(id:span.id) {
                    if let id=span.lexicalReference?.lexemeID {
                        semiticLexeme=try? await model.semiticLexicon?.lexeme(id:id,language:span.targetLanguageCode)
                    }
                }
                .onDisappear { speech.stop() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { speech.stop() } }
        }
    }
    private func save() async {
        guard let database = model.database else { return }
        saving = true
        defer { saving = false }
        do {
            let context = try passage.vocabularyContext(for: span)
            let draft = try VocabularyDraft(englishLemma: span.originalLemma, targetLanguage: span.targetLanguageCode,
                targetLemma: span.targetLemma, targetSurface: span.targetSurface, senseID: span.sourceSenseID,
                partOfSpeech: span.originalPartOfSpeech, exampleEnglish: context.english,
                exampleMixed: context.mixed,lexicalReference:span.lexicalReference).validated()
            let id: String
            if deck == "new" { id = try await database.createDeck(name: name) } else { id = deck }
            _ = try await database.saveVocabulary(draft, inDeck: id)
            try await model.refresh()
            saved = true
        } catch { self.error = error.localizedDescription }
    }
}
