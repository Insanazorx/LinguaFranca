import SwiftUI
import LinguaFrancaCore

struct LatinVocabularyView: View {
    @Environment(AppEnvironment.self) private var model
    @State private var query = ""
    @State private var pair = LatinVocabularyPair.all
    @AppStorage("latinVocabulary.wordType") private var wordType = LatinVocabularyWordType.all
    @State private var families: [LatinVocabularyFamily] = []
    @State private var summary: LatinVocabularySummary?
    @State private var loading = false
    @State private var more = false
    @State private var error: String?
    @State private var revision = 0
    var body: some View {
        List {
            Section {
                Text("Latin · Spanish · French").font(.headline)
                Text("Find shared origins and identical words in any two languages. English meanings do not decide which words belong together.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("Language pair", selection: $pair) {
                    ForEach(LatinVocabularyPair.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("latin-language-pair")
                Picker("Word type", selection: $wordType) {
                    ForEach(LatinVocabularyWordType.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("latin-word-type")
                Text("A–Z · \(wordType.title)").font(.caption).foregroundStyle(.secondary)
                if let summary {
                    Text("\(summary.families.formatted()) families · \(summary.nativeWords.formatted()) native words")
                        .font(.caption).foregroundStyle(Theme.forest)
                }
            }
            ForEach(families) { family in
                NavigationLink { LatinVocabularyFamilyView(family: family, wordType: wordType) } label: { LatinFamilyRow(family: family, wordType: wordType) }
            }
            if loading { ProgressView("Finding word families…") }
            else if more { Button("Load more families") { Task { await load(reset: false) } } }
            else if families.isEmpty && error == nil { ContentUnavailableView.search(text: query) }
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                Text("Historical links: Etymological Wordnet (2013), Wiktionary. Meanings: bundled WikDict dictionaries. Identical spellings are labelled separately; they can be false friends. Each word keeps its own meanings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Latin Vocab")
            .searchable(text: $query, prompt: "Latin, Spanish or French word")
            .onChange(of: wordType) { _, _ in revision += 1; families = []; summary = nil; more = false }
            .task(id: query + "|" + pair.rawValue + "|" + wordType.rawValue) {
                do { try await Task.sleep(for: .milliseconds(180)); try Task.checkCancellation(); await load(reset: true) } catch { }
            }
    }
    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        guard let latin = model.latinVocabulary else { error = "The word-family data is missing from this build."; return }
        if reset { revision += 1; families = []; more = false; summary = nil }
        let id = revision, text = query, selected = pair, selectedType = wordType, start = families.count
        loading = true; error = nil
        defer { if id == revision { loading = false } }
        do {
            let page = try await latin.search(text, pair: selected, wordType: selectedType, offset: start)
            try Task.checkCancellation(); guard id == revision, text == query, selected == pair, selectedType == wordType else { return }
            families += page.families; more = page.hasMore; summary = page.summary
        } catch is CancellationError { } catch { if id == revision { self.error = error.localizedDescription } }
    }
}

private struct LatinFamilyRow: View {
    @Environment(AppEnvironment.self) private var model
    let family: LatinVocabularyFamily
    let wordType: LatinVocabularyWordType
    @State private var members: [LatinVocabularyMember] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(family.displayWord).font(.headline).foregroundStyle(Theme.forest)
                Spacer()
                Text(family.hasRecordedOrigin ? "Shared origin" : "Same spelling")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if family.originWord != family.displayWord, family.hasRecordedOrigin {
                Text("Origin: " + family.originWord).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(["la", "es", "fr"], id: \.self) { code in
                let words = Array(Set(members.filter { $0.record.language == code }.map(\.record.headword))).sorted()
                if !words.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(code.uppercased()).font(.caption.weight(.semibold)).frame(width: 25, alignment: .leading)
                        Text(words.joined(separator: " · ")).font(.subheadline).lineLimit(2)
                    }.foregroundStyle(Theme.accent(code))
                }
            }
        }.padding(.vertical, 8)
            .task(id: family.id + "|" + wordType.rawValue) {
                members = []
                do {
                    let result = try await model.latinVocabulary?.members(of: family.id, wordType: wordType) ?? []
                    try Task.checkCancellation(); members = result
                } catch { }
            }
    }
}

private struct LatinVocabularyFamilyView: View {
    @Environment(AppEnvironment.self) private var model
    let family: LatinVocabularyFamily
    let wordType: LatinVocabularyWordType
    @State private var members: [LatinVocabularyMember] = []
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text(family.displayWord).font(.largeTitle).foregroundStyle(Theme.forest)
                Text(wordType.title).font(.caption).foregroundStyle(.secondary)
                if family.hasRecordedOrigin {
                    Text("Recorded common origin · \(family.originLanguage): \(family.originWord)").foregroundStyle(.secondary)
                    Text("Historical links describe the word, not every meaning. Compare the independent senses below.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Identical spelling · origin unverified").foregroundStyle(.secondary)
                    Text("These words share a spelling. They may have different origins or meanings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(["la", "es", "fr"].filter { family.languages.contains($0) }, id: \.self) { code in
                Section(Theme.language(code)) {
                    ForEach(members.filter { $0.record.language == code }) { member in
                        NavigationLink { DictionaryEntryView(record: member.record) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(member.record.headword).font(.title3).foregroundStyle(Theme.accent(code))
                                Text(member.record.partOfSpeech.capitalized).font(.caption).foregroundStyle(.secondary)
                                Text(member.record.definition.isEmpty ? member.record.english : member.record.definition).font(.subheadline)
                                if family.hasRecordedOrigin {
                                    Text(member.originPath.joined(separator: " ← ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5)
                        }
                    }
                }
            }
            Section("Source") {
                Text("Open a word to explore its dictionary entry or save it to a study list. Coverage is incomplete; English glosses are provided only to explain each independent sense.").font(.footnote)
                Text("Gerard de Melo · Etymological Wordnet 2013-02-08 · Wiktionary contributors · CC BY-SA 3.0").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(family.displayWord)
            .task(id: family.id) {
                do { members = try await model.latinVocabulary?.members(of: family.id, wordType: wordType) ?? [] }
                catch { self.error = error.localizedDescription }
            }
    }
}
