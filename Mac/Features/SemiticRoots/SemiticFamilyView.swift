import SwiftUI
import LinguaFrancaCore

struct SemiticRootsView: View {
    var embedded=false
    @Environment(AppEnvironment.self) private var model
    @State private var query=""
    @AppStorage("semitic.familyPair") private var pair=SemiticFamilyPair.all
    @State private var families:[SemiticFamily]=[]
    @State private var total=0
    @State private var loading=false
    @State private var more=false
    @State private var revision=0
    @State private var error:String?
    var body: some View {
        Group { if embedded { content } else { NavigationStack { content } } }
    }
    private var content: some View {
        List {
            Section {
                Label("Arabic · Hebrew · Classical Syriac",systemImage:"tree").font(.headline).foregroundStyle(Theme.forest)
                Text("Compare real words, meanings and usage across shared root families.").font(.subheadline).foregroundStyle(.secondary)
                Picker("Language combination",selection:$pair) {ForEach(SemiticFamilyPair.allCases) {Text($0.title).tag($0)}}
                    .accessibilityIdentifier("semitic-family-pair")
                Text("\(total.formatted()) families · A–Z by consonant labels").font(.caption).foregroundStyle(Theme.forest)
                NavigationLink {SemiticRootInventoryView(embedded:true)} label: {Label("All roots & Morphology Lab",systemImage:"books.vertical")}
            }
            Section {CatalogPracticeLauncher(source:.semitic,semiticPair:pair,query:query)}
            ForEach(families) { family in
                NavigationLink {SemiticFamilyDetailView(family:family)} label: {SemiticFamilyRow(family:family)}
            }
            if loading {ProgressView("Comparing roots…")}
            else if more {Button("Load more families") {Task {await load(reset:false)}}}
            else if families.isEmpty && error == nil {ContentUnavailableView.search(text:query)}
            if let error {Text(error).foregroundStyle(.red)}
            Section("Reading these comparisons") {
                Text("Matching consonants help you compare words; they do not prove a shared origin or an identical meaning. Recorded historical links and reviewed comparisons are labelled. Missing data does not mean a root is absent from a language.")
                Text("Arabic is standard Arabic, Hebrew is Modern Hebrew, and the Syriac pack is Classical. Modern Neo-Aramaic continuations are labelled separately when verified; otherwise modern usage stays unverified.")
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Semitic Roots")
            .searchable(text:$query,prompt:"k l b · k-t-b · native word or meaning")
            .task(id:query+"|"+pair.rawValue) {
                do {try await Task.sleep(for:.milliseconds(180));try Task.checkCancellation();await load(reset:true)} catch {}
            }
    }
    private func load(reset:Bool) async {
        guard reset || !loading else {return}
        guard let catalog=model.semiticLexicon?.families else {error="The root comparisons are missing. Rebuild with build.sh.";return}
        if reset {revision += 1;families=[];more=false}
        let token=revision,text=query,selected=pair,start=families.count
        loading=true;error=nil
        defer {if token==revision {loading=false}}
        do {
            let page=try await catalog.search(text,pair:selected,offset:start)
            try Task.checkCancellation();guard token==revision,text==query,selected==pair else {return}
            families += page.families;total=page.total;more=page.hasMore
        } catch is CancellationError {} catch {if token==revision {self.error=error.localizedDescription}}
    }
}
private struct SemiticFamilyRow: View {
    @Environment(AppEnvironment.self) private var model
    let family:SemiticFamily
    @State private var roots:[SemiticRoot]=[]
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {Text(family.label).font(.headline).foregroundStyle(Theme.forest);Spacer();Text(family.evidenceTitle).font(.caption).foregroundStyle(.secondary)}
            if !family.note.summary.isEmpty {Text(family.note.summary).font(.subheadline)}
            ForEach(roots) {root in
                HStack(alignment:.firstTextBaseline) {
                    Text(root.languageCode.uppercased()).font(.caption.bold()).frame(width:32,alignment:.leading)
                    Text(root.native).font(root.languageCode=="syc" ? .custom("NotoSansSyriac-Regular",size:23) : .title3)
                    Text("\(root.lexemeCount) words").font(.caption).foregroundStyle(.secondary)
                }.foregroundStyle(Theme.accent(root.languageCode))
            }
        }.padding(.vertical,7)
            .task(id:family.id) {do {roots=try await model.semiticLexicon?.families?.members(of:family.id) ?? []} catch {}}
    }
}
struct SemiticFamilyDetailView: View {
    @Environment(AppEnvironment.self) private var model
    let family:SemiticFamily
    @State private var roots:[SemiticRoot]=[]
    @State private var words:[String:[SemiticLexeme]]=[:]
    @State private var examples:[String:[SemiticExample]]=[:]
    @State private var error:String?
    var body: some View {
        List {
            Section {
                Text(family.label).font(.largeTitle).foregroundStyle(Theme.forest)
                Text(family.evidenceTitle).font(.caption).foregroundStyle(.secondary)
                if !family.note.summary.isEmpty {Text(family.note.summary).font(.title3)}
                Text(family.note.contrast.isEmpty ? "Compare the independent word senses below. Matching letters alone do not make these synonyms; different patterns and homographs may have unrelated meanings." : family.note.contrast)
                if !family.note.related.isEmpty {Text("Compare also: "+family.note.related.joined(separator:" · ")).font(.subheadline).foregroundStyle(Theme.forest)}
            }
            ForEach(SemiticLanguage.allCases) {language in
                Section(language.title) {
                    let matching=roots.filter{$0.languageCode==language.rawValue}
                    if matching.isEmpty {Text("No linked root recorded in this pack. This is a coverage gap, not proof of absence.").foregroundStyle(.secondary)}
                    ForEach(matching) {root in
                        NavigationLink {SemiticRootDetailView(root:root)} label: {
                            VStack(alignment:.leading,spacing:5) {
                                SemiticNativeText(text:root.native,language:root.languageCode,size:28)
                                Text("\(root.lexemeCount) derivatives · open all words & morphology").font(.caption)
                            }.foregroundStyle(Theme.accent(root.languageCode))
                        }
                        Text(family.note.usage[root.languageCode] ?? (root.languageCode=="syc" ? "Classical dictionary/corpus evidence. Survival and meaning in modern spoken Neo-Aramaic varieties have not been verified for this family." : "Recorded in the standard-language pack. Everyday spoken frequency and register have not been independently reviewed for this whole family."))
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(words[root.id] ?? []) {lexeme in
                            NavigationLink {SemiticLexemeDetailView(lexeme:lexeme)} label: {
                                VStack(alignment:.leading,spacing:5) {
                                    SemiticNativeText(text:lexeme.lemma,language:lexeme.languageCode)
                                    if !lexeme.transliteration.isEmpty {Text(lexeme.transliteration).font(.subheadline)}
                                    Text(lexeme.gloss).font(.subheadline)
                                    Text([lexeme.partOfSpeech,lexeme.pattern].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical,4)
                            }
                        }
                        DisclosureGroup("Source-recorded usage") {
                            if (examples[root.id] ?? []).isEmpty {Text("No aligned example is recorded for this root. Practice uses separate English learning scaffolds.").font(.footnote).foregroundStyle(.secondary)}
                            ForEach(examples[root.id] ?? []) {example in
                                VStack(alignment:.leading,spacing:6) {
                                    SemiticNativeText(text:example.text,language:root.languageCode,size:20)
                                    if !example.translation.isEmpty {Text(example.translation).font(.footnote)}
                                    Text(example.reference).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical,4)
                            }
                        }
                    }
                }
            }
            if !family.note.sources.isEmpty {Section("Comparison sources") {
                ForEach(family.note.sources,id:\.self) {source in if let url=URL(string:source) {Link(url.lastPathComponent, destination:url)}}
                Text("Learning notes reviewed 2 Nov 2026. Independent sense records remain authoritative; a historical family can contain several semantic branches.").font(.caption).foregroundStyle(.secondary)
            }}
            if let error {Text(error).foregroundStyle(.red)}
        }.navigationTitle(family.label)
            .task(id:family.id) {
                guard let lexicon=model.semiticLexicon else {return}
                do {
                    roots=try await lexicon.families?.members(of:family.id) ?? []
                    for root in roots {
                        let all=try await lexicon.lexemes(rootID:root.id,language:root.languageCode)
                        // Show distinct words/senses; the complete inventory remains one tap away.
                        let ranked=all.sorted {a,b in
                            func rank(_ x:SemiticLexeme) -> Int {
                                if CatalogContexts.make(english:x.gloss.split(separator:";").first.map(String.init) ?? "",pos:x.partOfSpeech) != nil {return 0}
                                if x.partOfSpeech=="verb" && ["I","Pa'al","Pe'al"].contains(x.pattern) {return 1}
                                return 2
                            }
                            return rank(a) != rank(b) ? rank(a)<rank(b) : (a.lemma,a.id)<(b.lemma,b.id)
                        }
                        words[root.id]=Array(ranked.prefix(12))
                        examples[root.id]=try await lexicon.examples(rootID:root.id,language:root.languageCode,limit:2)
                    }
                } catch {self.error=error.localizedDescription}
            }
    }
}
