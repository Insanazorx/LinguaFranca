import SwiftUI
import LinguaFrancaCore

struct DictionaryView:View {
    @Environment(AppEnvironment.self) private var model
    @State private var query=""
    @State private var mode="english"
    @State private var language="all"
    @State private var packs:[DictionaryPack]=[]
    @State private var groups:[DictionaryTranslationGroup]=[]
    @State private var records:[DictionaryRecord]=[]
    @State private var more=false
    @State private var loading=false
    @State private var error:String?
    @State private var revision=0
    var body:some View {
        NavigationStack {
            List {
                Section {
                    Picker("Search mode",selection:$mode) {
                        Text("English → all languages").tag("english")
                        Text("Browse dictionaries").tag("browse")
                    }.accessibilityIdentifier("dictionary-mode")
                    if mode=="browse" {
                        Picker("Language",selection:$language) {
                            Text("All dictionaries").tag("all")
                            ForEach(packs) {Text($0.metadata.displayName).tag($0.id)}
                        }.accessibilityIdentifier("dictionary-language")
                    }
                    NavigationLink {LatinVocabularyView()} label:{Label("Latin Vocab",systemImage:"point.3.connected.trianglepath.dotted")}
                    NavigationLink {DictionarySourcesView(packs:packs)} label:{Label("Installed dictionaries",systemImage:"books.vertical")}
                    NavigationLink {LanguagePackLibraryView()} label:{Label("Add a language pack",systemImage:"plus.circle")}
                    NavigationLink {SemiticRootsView(embedded:true)} label:{Label("Semitic Roots & Morphology",systemImage:"tree")}
                    Text(mode=="english" ? "Enter an English word or expression to see its recorded meanings in every installed language, including languages disabled for reading." : "Search English, a target word, an inflected form or a source transliteration. Everything is on your device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {Text(error).foregroundStyle(.red)}
                if mode=="english" {
                    if query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("One word, every language",systemImage:"character.book.closed",description:Text("Try an English word such as house or book."))
                    } else {
                        ForEach(groups) {group in
                            Section(group.pack.metadata.displayName) {
                                if group.records.isEmpty {
                                    Text("No recorded equivalent for this English expression.").font(.footnote).foregroundStyle(.secondary)
                                }
                                ForEach(group.records) {record in
                                    NavigationLink {DictionaryEntryView(record:record)} label:{DictionaryResultRow(record:record)}
                                }
                                if group.hasMore {
                                    Button("Show all meanings in this language"){language=group.id;mode="browse"}
                                }
                            }
                        }
                    }
                } else {
                    ForEach(records) {record in
                        NavigationLink {DictionaryEntryView(record:record)} label:{DictionaryResultRow(record:record)}
                    }
                    if !loading && more {Button("Load more"){Task{await load(reset:false)}}}
                    else if !loading && records.isEmpty && error==nil {ContentUnavailableView.search(text:query)}
                }
                if loading {ProgressView("Searching local dictionaries…")}
            }.navigationTitle("Dictionary")
                .searchable(text:$query,prompt:mode=="english" ? "English word or expression":"English or target expression")
                .task(id:mode+":"+language+":"+query+":"+String(model.languagePacks.count)) {
                    do {try await Task.sleep(for:.milliseconds(220));try Task.checkCancellation();await load(reset:true)} catch { }
                }
        }
    }
    private func load(reset:Bool) async {
        guard let dictionary=model.dictionary else {error="The offline search index is missing. Rebuild with build.sh.";return}
        if reset {revision+=1;records=[];groups=[];more=false}
        let id=revision,requestedQuery=query,requestedLanguage=language,requestedMode=mode,start=records.count
        loading=true;error=nil
        defer{if id==revision {loading=false}}
        do {
            packs=await dictionary.packs()
            if requestedMode=="english" {
                let result=try await dictionary.englishTranslations(requestedQuery)
                try Task.checkCancellation()
                guard id==revision,requestedQuery==query,mode==requestedMode else{return}
                groups=result
            } else {
                let page=try await dictionary.search(requestedQuery,language:requestedLanguage=="all" ? nil:requestedLanguage,offset:start)
                try Task.checkCancellation()
                guard id==revision,requestedQuery==query,requestedLanguage==language,mode==requestedMode else{return}
                records+=page.records;more=page.hasMore
            }
        } catch is CancellationError { } catch {if id==revision {self.error=error.localizedDescription}}
    }
}


private struct DictionaryResultRow:View {
    let record:DictionaryRecord
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            SemiticOrLatinVocabularyText(text:record.headword,language:record.language).foregroundStyle(Theme.accent(record.language))
            Text(record.english).font(.subheadline).lineLimit(2)
            if record.definition != record.english {Text(record.definition).font(.caption).foregroundStyle(.secondary).lineLimit(2)}
            Text("\(Theme.language(record.language)) · \(record.partOfSpeech)\(record.kind == .root ? " · Root":"")").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical,5)
    }
}

private struct DictionarySourcesView:View {
    let packs:[DictionaryPack]
    var body:some View {
        List {
            ForEach(packs) {pack in
                Section(pack.metadata.displayName) {
                    LabeledContent("English senses",value:"\(pack.entries)")
                    if pack.lexemes>0 {LabeledContent("Native lexemes",value:"\(pack.lexemes)")}
                    if pack.roots>0 {LabeledContent("Roots",value:"\(pack.roots)")}
                    LabeledContent("Source forms",value:"\(pack.forms)")
                    Text(pack.metadata.licenseMetadata["attribution"] ?? pack.metadata.version).font(.footnote)
                    if let license=pack.metadata.licenseMetadata["license"] {Text(license).font(.caption).foregroundStyle(.secondary)}
                    if let corpus=pack.metadata.licenseMetadata["corpusLicense"] {Text("ETCBC · \(corpus)").font(.caption).foregroundStyle(.secondary)}
                }
            }
        }.navigationTitle("Downloaded dictionaries")
    }
}

private struct DictionarySave:Identifiable {let id=UUID();let draft:VocabularyDraft}

struct DictionaryEntryView:View {
    @Environment(AppEnvironment.self) private var model
    let record:DictionaryRecord
    @State private var detail:DictionaryDetail?
    @State private var selected=""
    @State private var forms:[DictionaryForm]=[]
    @State private var more=false
    @State private var loadingForms=false
    @State private var root:SemiticRoot?
    @State private var save:DictionarySave?
    @State private var error:String?
    @State private var speech=SentenceSpeechController()
    var body:some View {
        List {
            Section {
                SemiticOrLatinVocabularyText(text:selected.isEmpty ? record.headword:selected,language:record.language).font(.title)
                Text(record.english).font(.title2).textSelection(.enabled)
                Text("\(Theme.language(record.language)) · \(record.partOfSpeech.capitalized)").font(.subheadline).foregroundStyle(.secondary)
                if !record.transliteration.isEmpty && !record.transliteration.hasPrefix("ETCBC ") {Text(record.transliteration).textSelection(.enabled)}
                Text(record.definition).textSelection(.enabled)
            }
            if let detail {
                Section("Expressions in this sense") {
                    if detail.translations.count>1 {
                        Picker("Expression",selection:$selected) {ForEach(detail.translations,id:\.self){Text($0).tag($0)}}
                    }
                    Button("Save to a study list",systemImage:"bookmark") {save=DictionarySave(draft:detail.vocabularyDraft(target:selected))}
                    Button("Pronounce this expression",systemImage:"speaker.wave.2") {speech.speak([.init(text:selected,languageCode:record.language)])}
                        .disabled(!SentenceSpeechController.hasLocalVoice(record.language))
                }
                if !detail.etymology.isEmpty {Section("Etymology"){Text(detail.etymology).textSelection(.enabled)}}
                if let root {Section {NavigationLink("Explore root & morphology"){SemiticRootDetailView(root:root)}}}
                if !forms.isEmpty || loadingForms {
                    Section {
                        ForEach(forms) {form in
                            VStack(alignment:.leading,spacing:6) {
                                SemiticOrLatinVocabularyText(text:form.surface,language:record.language)
                                Text(form.analysis).font(.caption).foregroundStyle(.secondary)
                                if !form.transliteration.isEmpty && !form.transliteration.hasPrefix("ETCBC ") {Text(form.transliteration).font(.caption)}
                                if let url=sourceURL(form.source) {Link("Form source",destination:url).font(.caption)}
                            }.padding(.vertical,4)
                        }
                        if loadingForms {ProgressView()}
                        else if more {Button("Load more forms"){Task{await loadForms(reset:false)}}}
                    } header:{Text("Recorded forms")} footer:{Text("These are the source's forms for this spelling. Some may belong to other senses.")}
                }
                Section("Sources") {
                    if let source=detail.sources["source"] {Text(source)}
                    if let license=detail.sources["license"] {Text(license).font(.footnote)}
                    ForEach(["wiktionary","url"],id:\.self) {key in
                        if let raw=detail.sources[key],let url=sourceURL(raw) {Link(key == "wiktionary" ? "Wiktionary entry":"Lexical source",destination:url)}
                    }
                }
            } else if error == nil {ProgressView("Opening dictionary entry…")}
            if let error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("Dictionary entry").inlineNavigationTitle()
            .task(id:record.id) {
                do {
                    detail=try await model.dictionary?.detail(record)
                    selected=detail?.translations.contains(record.headword)==true ? record.headword:detail?.translations.first ?? record.headword
                    if let id=detail?.rootID {root=try await model.semiticLexicon?.root(id:id,language:record.language)}
                } catch {self.error=error.localizedDescription}
            }
            .task(id:selected) {if !selected.isEmpty {await loadForms(reset:true)}}
            .sheet(item:$save) {SemiticSaveSheet(draft:$0.draft)}
            .onDisappear {speech.stop()}
    }
    private func sourceURL(_ value:String) -> URL? {guard let url=URL(string:value),url.scheme=="https" else{return nil};return url}
    private func loadForms(reset:Bool) async {
        guard let dictionary=model.dictionary,let detail else{return}
        let target=selected
        if reset {forms=[];more=false}
        let start=forms.count;loadingForms=true
        defer{if target==selected {loadingForms=false}}
        do {
            let page=try await dictionary.forms(detail,target:target,offset:start)
            try Task.checkCancellation()
            guard target==selected else{return};forms+=page.forms;more=page.hasMore
        } catch is CancellationError { } catch {self.error=error.localizedDescription}
    }
}
