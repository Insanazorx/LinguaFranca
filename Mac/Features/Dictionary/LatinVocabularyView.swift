import SwiftUI
import LinguaFrancaCore

struct LatinVocabularyView:View {
    @Environment(AppEnvironment.self) private var model
    @State private var query=""
    @State private var families:[LatinVocabularyFamily]=[]
    @State private var loading=false
    @State private var more=false
    @State private var error:String?
    @State private var revision=0
    var body:some View {
        List {
            Section {
                Text("Latin · Spanish · French").font(.headline)
                Text("Explore words with a recorded common Latin origin. Each word keeps its own meaning; a shared history does not make every use interchangeable.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(families) {family in
                NavigationLink {LatinVocabularyFamilyView(family:family)} label:{LatinFamilyRow(family:family)}
            }
            if loading {ProgressView("Finding word families…")}
            else if more {Button("Load more families"){Task{await load(reset:false)}}}
            else if families.isEmpty && error==nil {ContentUnavailableView.search(text:query)}
            if let error {Text(error).foregroundStyle(.red)}
            Section {
                Text("Origins: Gerard de Melo’s Etymological Wordnet, Wiktionary extraction from 2013. Meanings: bundled WikDict dictionaries. Coverage is incomplete; spelling resemblance alone is never used to form a family.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Latin Vocab")
            .searchable(text:$query,prompt:"English, Latin, Spanish or French")
            .task(id:query) {
                do {try await Task.sleep(for:.milliseconds(180));try Task.checkCancellation();await load(reset:true)} catch { }
            }
    }
    private func load(reset:Bool) async {
        guard let latin=model.latinVocabulary else {error="The Latin word-family data is missing from this build.";return}
        if reset {revision+=1;families=[];more=false}
        let id=revision,text=query,start=families.count
        loading=true;error=nil;defer {if id==revision {loading=false}}
        do {
            let page=try await latin.search(text,offset:start)
            try Task.checkCancellation();guard id==revision,text==query else{return}
            families+=page.families;more=page.hasMore
        } catch is CancellationError { } catch {if id==revision {self.error=error.localizedDescription}}
    }
}

private struct LatinFamilyRow:View {
    @Environment(AppEnvironment.self) private var model
    let family:LatinVocabularyFamily
    @State private var members:[LatinVocabularyMember]=[]
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {Text(family.latin).font(.headline).foregroundStyle(Theme.accent("la"));Spacer();Text(family.english).font(.subheadline)}
            ForEach(["es","fr"],id:\.self) {code in
                let words=Array(Set(members.filter{$0.record.language==code}.map(\.record.headword))).sorted()
                if !words.isEmpty {Text(Theme.language(code)+": "+words.joined(separator:", ")).font(.subheadline).foregroundStyle(Theme.accent(code))}
            }
        }.padding(.vertical,6)
            .task(id:family.id) {members=(try? await model.latinVocabulary?.members(of:family.id)) ?? []}
    }
}

private struct LatinVocabularyFamilyView:View {
    @Environment(AppEnvironment.self) private var model
    let family:LatinVocabularyFamily
    @State private var members:[LatinVocabularyMember]=[]
    @State private var error:String?
    var body:some View {
        List {
            Section {
                Text(family.latin).font(.largeTitle).foregroundStyle(Theme.accent("la"))
                Text(family.english+" · "+family.partOfSpeech).foregroundStyle(.secondary)
            }
            ForEach(["la","es","fr"],id:\.self) {code in
                Section(Theme.language(code)) {
                    ForEach(members.filter{$0.record.language==code}) {member in
                        NavigationLink {DictionaryEntryView(record:member.record)} label: {
                            VStack(alignment:.leading,spacing:8) {
                                Text(member.record.headword).font(.title3).foregroundStyle(Theme.accent(code))
                                Text(member.record.definition.isEmpty ? member.record.english:member.record.definition).font(.subheadline)
                                if code != "la" {Text(member.originPath.joined(separator:" ← ")).font(.caption).foregroundStyle(.secondary)}
                            }.padding(.vertical,4)
                        }
                    }
                }
            }
            Section("Source") {
                Text("Recorded historical origin, not a guarantee of identical modern meaning. Open a word to see its dictionary sense or save it to a study list.").font(.footnote)
                Text("Gerard de Melo · Etymological Wordnet 2013-02-08 · English Wiktionary contributors · CC BY-SA 3.0").font(.caption).foregroundStyle(.secondary)
            }
            if let error {Text(error).foregroundStyle(.red)}
        }.navigationTitle(family.latin)
            .task(id:family.id) {
                do {members=try await model.latinVocabulary?.members(of:family.id) ?? []} catch {self.error=error.localizedDescription}
            }
    }
}
