import SwiftUI
import LinguaFrancaCore

struct SemiticNativeText: View {
    let text: String
    let language: String
    var size: CGFloat = 24
    var body: some View {
        Text(text).font(language == "syc" ? .custom("NotoSansSyriac-Regular",size:size,relativeTo:.body) : .system(size:size))
            .environment(\.layoutDirection,.rightToLeft).multilineTextAlignment(.trailing)
            .frame(maxWidth:.infinity,alignment:.trailing)
    }
}

struct SemiticRootsView: View {
    var embedded=false
    init(embedded:Bool=false) {self.embedded=embedded}
    @Environment(AppEnvironment.self) private var model
    @State private var language = "all"
    @State private var search = ""
    @State private var roots: [SemiticRoot] = []
    @State private var loading = false
    @State private var more = true
    @State private var error: String?
    @State private var save: VocabularyDraft?
    var body: some View {
        Group { if embedded { content } else { NavigationStack { content } } }
    }
    private var content: some View {
            List {
                Section {
                    Picker("Language",selection:$language) {
                        Text("All languages").tag("all")
                        ForEach(SemiticLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text("Explore source-recorded roots and derivatives. A shared historical family is shown only when the lexical sources document it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(roots) { root in
                    NavigationLink {
                        SemiticRootDetailView(root:root)
                    } label: {
                        VStack(alignment:.leading,spacing:6) {
                            SemiticNativeText(text:root.native,language:root.languageCode).foregroundStyle(Theme.accent(root.languageCode))
                            if !root.transliteration.isEmpty { Text(root.transliteration).font(.subheadline) }
                            Text(root.meaning).lineLimit(2).font(.subheadline)
                            HStack {
                                Text("\(Theme.language(root.languageCode)) · \(root.lexemeCount) derivatives")
                                if model.vocabulary.contains(where: { $0.draft.lexicalReference?.rootID == root.id }) { Image(systemName:"bookmark.fill").accessibilityLabel("Saved vocabulary in this family") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,5)
                    }.contextMenu { Button("Save root to list",systemImage:"folder.badge.plus") { save=root.vocabularyDraft } }
                }
                if loading { ProgressView("Loading roots…") }
                else if more && !roots.isEmpty { Button("Load more") { Task { await load(reset:false) } } }
                else if roots.isEmpty && error == nil { ContentUnavailableView.search(text:search) }
            }
            .navigationTitle("Semitic Roots")
            .searchable(text:$search,prompt:"Root, meaning or transliteration")
            .task(id:language+":"+search) {
                do { try await Task.sleep(for:.milliseconds(200)); try Task.checkCancellation(); await load(reset:true) } catch { }
            }
            .sheet(isPresented:Binding(get:{save != nil},set:{if !$0 { save=nil }})) { if let save { SemiticSaveSheet(draft:save) } }
    }
    @MainActor private func load(reset: Bool) async {
        guard let lexicon=model.semiticLexicon else { error="Semitic language packs are unavailable. Rebuild with build.sh.";return }
        if reset { roots=[]; more=true }
        loading=true; error=nil
        defer { loading=false }
        do {
            let result=try await lexicon.roots(language:language == "all" ? nil : language,search:search,offset:roots.count)
            try Task.checkCancellation(); roots+=result; more=result.count==50
        } catch is CancellationError { } catch { self.error=error.localizedDescription }
    }
}

struct SemiticRootDetailView: View {
    @Environment(AppEnvironment.self) private var model
    let root: SemiticRoot
    @State private var lexemes: [SemiticLexeme] = []
    @State private var relationships: [SemiticRelationship] = []
    @State private var examples: [SemiticExample] = []
    @State private var save: VocabularyDraft?
    @State private var error: String?
    private var saved: [VocabularyItem] { model.vocabulary.filter { $0.draft.targetLanguage==root.languageCode && $0.draft.lexicalReference?.rootID==root.id } }
    var body: some View {
        List {
            Section {
                SemiticNativeText(text:root.native,language:root.languageCode,size:38)
                Text(Theme.language(root.languageCode)).font(.subheadline).foregroundStyle(.secondary)
                if !root.transliteration.isEmpty { Text(root.transliteration) }
                Text(root.meaning)
                if !root.etymology.isEmpty { Text(root.etymology).font(.footnote).foregroundStyle(.secondary) }
                Link("Lexical source",destination:URL(string:root.source)!)
            }
            Section {
                Button("Save root to study list",systemImage:"folder.badge.plus") { save=root.vocabularyDraft }
                NavigationLink("Morphology Lab") { MorphologyLabView(root:root) }
                if let group=VocabularyLanguageGroup.grouped(saved).first {
                    NavigationLink("Write with saved vocabulary") {
                        VocabularyLanguageGroupView(group:group,deckID:"",deckName:"Root family",practiceGroupID:"root:"+root.id)
                    }
                } else { Text("Save the root or a derivative to a list to use it in target-language writing.").font(.footnote).foregroundStyle(.secondary) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Section("Derived lexemes · \(lexemes.count)") {
                ForEach(lexemes) { lexeme in
                    NavigationLink { SemiticLexemeDetailView(lexeme:lexeme) } label: {
                        VStack(alignment:.leading,spacing:5) {
                            SemiticNativeText(text:lexeme.lemma,language:lexeme.languageCode)
                            if !lexeme.transliteration.isEmpty { Text(lexeme.transliteration).font(.subheadline) }
                            Text(lexeme.gloss).font(.subheadline)
                            Text([lexeme.partOfSpeech,lexeme.pattern].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.contextMenu { Button("Save lexeme to list") { save=lexeme.vocabularyDraft } }
                }
            }
            Section("Documented historical relationships") {
                if relationships.isEmpty { Text("No verified cross-language relationship is recorded in this pack.").foregroundStyle(.secondary) }
                ForEach(relationships) { relationship in
                    NavigationLink { SemiticRootDetailView(root:relationship.root) } label: {
                        VStack(alignment:.leading,spacing:4) {
                            SemiticNativeText(text:relationship.root.native,language:relationship.root.languageCode)
                            Text(Theme.language(relationship.root.languageCode)+" · "+relationship.family).font(.caption)
                            Text(relationship.evidence).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !examples.isEmpty {
                Section("Referenced usage") {
                    ForEach(examples) { example in
                        VStack(alignment:.leading,spacing:8) {
                            SemiticNativeText(text:example.text,language:root.languageCode,size:20)
                            if !example.transliteration.isEmpty { Text(example.transliteration).font(.footnote) }
                            Text(example.translation).font(.subheadline)
                            Text(example.reference).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,5)
                    }
                }
            }
        }
        .navigationTitle("Root family").navigationBarTitleDisplayMode(.inline)
        .task(id:root.id) {
            guard let catalog=model.semiticLexicon else { return }
            do {
                lexemes=try await catalog.lexemes(rootID:root.id,language:root.languageCode)
                relationships=try await catalog.relationships(rootID:root.id,language:root.languageCode)
                examples=try await catalog.examples(rootID:root.id,language:root.languageCode)
            } catch { self.error=error.localizedDescription }
        }
        .sheet(isPresented:Binding(get:{save != nil},set:{if !$0 {save=nil}})) { if let save { SemiticSaveSheet(draft:save) } }
    }
}

struct SemiticLexemeDetailView: View {
    @Environment(AppEnvironment.self) private var model
    let lexeme: SemiticLexeme
    @State private var forms: [SemiticWordForm] = []
    @State private var root: SemiticRoot?
    @State private var save: VocabularyDraft?
    @State private var speech = SentenceSpeechController()
    var body: some View {
        List {
            Section {
                SemiticNativeText(text:lexeme.lemma,language:lexeme.languageCode,size:34)
                Text(lexeme.transliteration); Text(lexeme.gloss)
                Text(lexeme.pattern).foregroundStyle(.secondary)
                if SentenceSpeechController.hasLocalVoice(lexeme.languageCode) {
                    Button(speech.isSpeaking ? "Stop pronunciation" : "Pronounce") {
                        if speech.isSpeaking { speech.stop() } else { speech.speak([.init(text:lexeme.lemma,languageCode:lexeme.languageCode)]) }
                    }
                } else { Text("No verified local voice is available for this variety. Use the source transliteration.").font(.footnote).foregroundStyle(.secondary) }
                Button("Save lexeme to list") { save=lexeme.vocabularyDraft }
                if let root { NavigationLink("Root family") { SemiticRootDetailView(root:root) }; NavigationLink("Morphology Lab") { MorphologyLabView(root:root,initialLexemeID:lexeme.id) } }
                Link("Lexical source",destination:URL(string:lexeme.source)!)
            }
            Section("Source-recorded forms · \(forms.count)") {
                ForEach(forms) { form in
                    Button { save=form.vocabularyDraft(for:lexeme) } label: {
                        VStack(alignment:.leading,spacing:5) {
                            SemiticNativeText(text:form.surface,language:lexeme.languageCode)
                            if !form.transliteration.isEmpty { Text(form.transliteration).font(.subheadline) }
                            Text(form.analysis).font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary)
                    }
                }
            }
        }.navigationTitle("Lexeme").navigationBarTitleDisplayMode(.inline)
        .task(id:lexeme.id) {
            guard let catalog=model.semiticLexicon else{return}
            do {
                forms=try await catalog.verifiedForms(for:lexeme.reference)
                if let id=lexeme.rootID { root=try await catalog.root(id:id,language:lexeme.languageCode) }
            } catch { model.errorMessage=error.localizedDescription }
        }
        .sheet(isPresented:Binding(get:{save != nil},set:{if !$0 {save=nil}})) { if let save { SemiticSaveSheet(draft:save) } }
        .onDisappear { speech.stop() }
    }
}

struct MorphologyLabView: View {
    @Environment(AppEnvironment.self) private var model
    let root: SemiticRoot
    var initialLexemeID: String? = nil
    @State private var lexemes: [SemiticLexeme] = []
    @State private var selection = ""
    @State private var pattern = "all"
    @State private var tense = "all"
    @State private var person = "all"
    @State private var number = "all"
    @State private var gender = "all"
    @State private var mood = "all"
    @State private var voice = "all"
    @State private var nominalState = "all"
    @State private var vowelized = true
    @State private var forms: [SemiticWordForm] = []
    @State private var save: VocabularyDraft?
    private var patterns: [String] { Array(Set(lexemes.map(\.pattern).filter{!$0.isEmpty})).sorted() }
    private var choices: [SemiticLexeme] { lexemes.filter { pattern=="all" || $0.pattern==pattern } }
    private var visible: [SemiticWordForm] { forms.filter { form in [tense,person,number,gender,mood,voice,nominalState].filter{$0 != "all"}.allSatisfy {form.tags.contains($0)} } }
    var body: some View {
        Form {
            Section {
                SemiticNativeText(text:root.native,language:root.languageCode)
                Picker("Pattern / stem",selection:$pattern) { Text("All recorded patterns").tag("all"); ForEach(patterns,id:\.self) { Text($0).tag($0) } }
                Picker("Lexeme",selection:$selection) { ForEach(choices) { Text($0.lemma+" · "+String($0.gloss.prefix(45))).tag($0.id) } }
                featurePicker("Tense / form",selection:$tense,values:["past","non-past","present","future","perfect","imperfect","infinitive","imperative","participle"])
                featurePicker("Person",selection:$person,values:["first-person","second-person","third-person"])
                featurePicker("Number",selection:$number,values:["singular","dual","plural"])
                featurePicker("Gender",selection:$gender,values:["masculine","feminine"])
                featurePicker("Mood",selection:$mood,values:["indicative","subjunctive","jussive"])
                featurePicker("Voice",selection:$voice,values:["active","passive"])
                featurePicker("Nominal state",selection:$nominalState,values:["indefinite","definite","construct","absolute","emphatic"])
                Toggle("Show vowel marks",isOn:$vowelized)
            }
            Section("Verified inventory · \(visible.count)") {
                Text("Forms are recorded in the dictionary or corpus. Unsupported combinations are never invented. Source attestation does not certify every possible sentence context.").font(.footnote).foregroundStyle(.secondary)
                if visible.isEmpty { Label("Unsupported selection in this pack",systemImage:"questionmark.circle").foregroundStyle(.secondary) }
                ForEach(visible) { form in
                    VStack(alignment:.leading,spacing:6) {
                        SemiticNativeText(text:vowelized ? form.surface : SemiticUnicode.key(form.surface),language:root.languageCode)
                        Text(form.transliteration.isEmpty ? "No source transliteration is supplied for this form." : form.transliteration).font(.subheadline).foregroundStyle(.secondary)
                        Text(form.analysis).font(.caption)
                        Text(form.status.rawValue.capitalized).font(.caption).foregroundStyle(Theme.forest)
                        if let lexeme=lexemes.first(where:{$0.id==form.lexemeID}) {
                            Text(lexeme.gloss).font(.subheadline)
                            Button("Save this form") { save=form.vocabularyDraft(for:lexeme) }
                        }
                        Link("Form source",destination:URL(string:form.source)!).font(.caption)
                    }.padding(.vertical,5)
                }
            }
        }.navigationTitle("Morphology Lab").navigationBarTitleDisplayMode(.inline)
        .task { do { lexemes=try await model.semiticLexicon?.lexemes(rootID:root.id,language:root.languageCode) ?? []; selection=initialLexemeID ?? lexemes.first?.id ?? "" } catch { model.errorMessage=error.localizedDescription } }
        .onChange(of:pattern) { _,_ in selection=choices.first?.id ?? "" }
        .task(id:selection) {
            do { if let lexeme=lexemes.first(where:{$0.id==selection}) { forms=try await model.semiticLexicon?.verifiedForms(for:lexeme.reference) ?? [] } else { forms=[] } }
            catch { model.errorMessage=error.localizedDescription }
        }
        .sheet(isPresented:Binding(get:{save != nil},set:{if !$0 {save=nil}})) { if let save { SemiticSaveSheet(draft:save) } }
    }
    private func featurePicker(_ title: String, selection: Binding<String>, values:[String]) -> some View {
        Picker(title,selection:selection) { Text("Any").tag("all"); ForEach(values,id:\.self) { Text($0.replacingOccurrences(of:"-",with:" ").capitalized).tag($0) } }
    }
}

struct SemiticSaveSheet: View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: VocabularyDraft
    @State private var deck = ""
    @State private var name = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { SemiticOrLatinVocabularyText(text:draft.targetSurface,language:draft.targetLanguage); Text(draft.englishLemma) }
                Section("Study list") {
                    Picker("List",selection:$deck) { Text("Create a new list").tag(""); ForEach(model.decks) { Text($0.name).tag($0.id) } }
                    if deck.isEmpty { TextField("New list name",text:$name) }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Save") { Task { await save() } }.disabled(saving || (deck.isEmpty && name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
                }
            }.navigationTitle("Save to list").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { deck=model.decks.first?.id ?? "" }
        }
    }
    @MainActor private func save() async {
        guard let database=model.database else{return};saving=true;defer{saving=false}
        do {
            let id: String
            if deck.isEmpty { id=try await database.createDeck(name:name) } else { id=deck }
            _=try await database.saveVocabulary(draft,inDeck:id);try await model.refresh();dismiss()
        } catch { self.error=error.localizedDescription }
    }
}
