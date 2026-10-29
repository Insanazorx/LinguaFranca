import SwiftUI
import LinguaFrancaCore

struct StudyWordDictionaryView:View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    let word:VocabularyDraft
    var dismissTitle: String = "Back to cards"
    @State private var inspection:VocabularyDictionaryInspection?
    @State private var error:String?
    var body:some View {
        NavigationStack {
            Group {
                if let exact=inspection?.exact {
                    DictionaryEntryView(record:exact)
                } else {
                    List {
                        Section {
                            SemiticOrLatinVocabularyText(text:word.targetSurface,language:word.targetLanguage).font(.largeTitle)
                            Text(word.englishLemma).font(.title2)
                            Text(Theme.language(word.targetLanguage)+" · "+word.partOfSpeech).foregroundStyle(.secondary)
                            if !word.exampleEnglish.isEmpty {Text(word.exampleEnglish).font(.subheadline).italic()}
                        }
                        if let inspection {
                            Section("Dictionary meanings") {
                                ForEach(inspection.candidates) {record in
                                    NavigationLink {DictionaryEntryView(record:record)} label: {
                                        VStack(alignment:.leading,spacing:6) {
                                            Text(record.headword).foregroundStyle(Theme.accent(record.language))
                                            Text(record.definition.isEmpty ? record.english:record.definition).font(.subheadline)
                                        }.padding(.vertical,4)
                                    }
                                }
                                if inspection.candidates.isEmpty {Text("No matching entry was found in the installed dictionary. Your saved meaning and example are shown above.").font(.footnote).foregroundStyle(.secondary)}
                            }
                        } else if error==nil {ProgressView("Opening dictionary…")}
                        if let error {Text(error).foregroundStyle(.red)}
                    }.navigationTitle("Dictionary entry")
                }
            }
            .toolbar {ToolbarItem(placement:.cancellationAction){Button(dismissTitle){dismiss()}.keyboardShortcut(.cancelAction).accessibilityIdentifier("back-to-cards")}}
            .task {
                guard let dictionary=model.dictionary else {error="The installed dictionary is unavailable.";return}
                do {inspection=try await dictionary.inspect(word)} catch {self.error=error.localizedDescription}
            }
        }.foregroundStyle(.primary).tint(Theme.forest)
        #if os(macOS)
        .frame(minWidth:560,idealWidth:620,minHeight:560,idealHeight:700)
        #else
        .presentationDetents([.large])
        #endif
    }
}
