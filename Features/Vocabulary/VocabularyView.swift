import SwiftUI
import LinguaFrancaCore

struct VocabularyView: View {
    @Environment(AppEnvironment.self) private var model
    @State private var query = ""
    @State private var deckID = ""
    @State private var language = ""
    @State private var memberIDs: Set<String> = []
    @State private var selectedWordID: String?
    @State private var selectedIDs: Set<String> = []
    @State private var selecting = false
    @State private var showEditor = false
    @State private var edited: VocabularyItem?
    @State private var showLists = false
    @State private var deleteItem: VocabularyItem?
    @State private var membershipLoading = false
    @State private var practiceLoading = false
    #if os(iOS)
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var review: VocabularyReviewPresentation?
    #endif
    private var scoped: [VocabularyItem] {
        model.vocabulary.filter { deckID.isEmpty || memberIDs.contains($0.id) }
    }
    private var visible: [VocabularyItem] {
        let needle = OfflineDictionary.key(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return scoped.filter {
            (language.isEmpty || $0.draft.targetLanguage == language) && (needle.isEmpty ||
                OfflineDictionary.key([$0.draft.targetSurface, $0.draft.targetLemma, $0.draft.englishLemma, $0.draft.exampleEnglish].joined(separator: " ")).contains(needle))
        }.sorted {
            let a = OfflineDictionary.key($0.draft.targetSurface), b = OfflineDictionary.key($1.draft.targetSurface)
            return a == b ? $0.id < $1.id : a < b
        }
    }
    private var currentWord: VocabularyItem? { model.vocabulary.first { $0.id == selectedWordID } }
    private var deckName: String { model.decks.first { $0.id == deckID }?.name ?? "All vocabulary" }
    var body: some View {
        Group {
            #if os(macOS)
            NavigationStack {
                HSplitView {
                    wordBrowser.frame(minWidth: 280, idealWidth: 330, maxWidth: 440)
                    detail.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }.navigationTitle("Vocabulary")
            }
            #else
            NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
                wordBrowser.navigationTitle("Vocabulary")
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
            } detail: {
                NavigationStack { detail }
            }.navigationSplitViewStyle(.balanced)
            #endif
        }
        .sheet(isPresented: $showEditor) {
            VocabularyEditor(item: edited, initialDeckID: deckID).environment(model)
            #if os(macOS)
                .nativeSheetSize()
            #endif
        }
        .sheet(isPresented: $showLists) {
            DeckManagerView().environment(model)
            #if os(macOS)
                .nativeSheetSize(width: 560, height: 540)
            #endif
        }
        .task(id: deckID) { await loadMemberships() }
        .onChange(of: model.decks) { _, decks in
            if !deckID.isEmpty && !decks.contains(where: { $0.id == deckID }) { deckID = "" }
            Task { await loadMemberships() }
        }
        .onChange(of: model.vocabulary) { _, words in
            let valid = Set(words.map(\.id))
            selectedIDs.formIntersection(valid)
            if let id = selectedWordID, !valid.contains(id) { selectedWordID = nil }
            Task { await loadMemberships() }
        }
        .onChange(of: deckID) { _, _ in language = ""; resetSelection() }
        .onChange(of: language) { _, _ in resetSelection() }
        .alert("Delete this word?", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } })) {
            Button("Delete", role: .destructive) {
                if let item = deleteItem { Task { await model.perform { try await $0.deleteVocabulary(id: item.id) } } }
                deleteItem = nil
            }
            Button("Cancel", role: .cancel) { deleteItem = nil }
        } message: { Text("This removes it from every list and deletes its study history.") }
        #if os(iOS)
        .fullScreenCover(item: $review) { ReviewSessionView(cards: $0.cards).environment(model) }
        #endif
    }
    private var wordBrowser: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Study list", selection: $deckID) {
                    Text("All vocabulary").tag("")
                    ForEach(model.decks) { Text("\($0.name) · \($0.wordCount)").tag($0.id) }
                }.pickerStyle(.menu).accessibilityIdentifier("vocabulary-list-picker")
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a word or meaning", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Picker("Language", selection: $language) {
                        Text("All languages").tag("")
                        ForEach(Array(Set(scoped.map { $0.draft.targetLanguage })).sorted(), id: \.self) { Text(Theme.language($0)).tag($0) }
                    }.pickerStyle(.menu).labelsHidden()
                    Spacer()
                    Text("\(visible.count) words").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).background(Theme.forest.opacity(0.06))
            Divider()
            List(selection: $selectedWordID) {
                if membershipLoading { ProgressView("Opening list…") }
                else if visible.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Your word collection" : "No matching words", systemImage: "character.book.closed", description: Text("Save words from a reading or the dictionary, or add your own."))
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { item in
                    #if os(macOS)
                    Button { selectedWordID = item.id } label: { row(item) }.buttonStyle(.plain)
                        .tag(item.id).listRowBackground(item.id == selectedWordID ? Theme.forest.opacity(0.13) : Color.clear)
                        .contextMenu { wordActions(item) }
                    #else
                    NavigationLink(value: item.id) { row(item) }.tag(item.id)
                        .contextMenu { wordActions(item) }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleteItem = item }
                            if !deckID.isEmpty { Button("Remove from list") { remove(item) }.tint(Theme.forest) }
                        }
                    #endif
                }
            }.listStyle(.plain)
            Divider()
            VStack(spacing: 10) {
                if selecting {
                    HStack {
                        Text("\(selectedIDs.count) selected").font(.caption)
                        Spacer()
                        Button("Select visible") { selectedIDs.formUnion(visible.map(\.id)) }.font(.caption)
                        Button("Clear") { selectedIDs = [] }.font(.caption)
                    }
                }
                HStack {
                    Button(selecting ? "Done" : "Select words") { selecting.toggle(); if !selecting { selectedIDs = [] } }
                    Spacer()
                    Button {
                        practice(selecting ? selectedIDs : Set(visible.map(\.id)))
                    } label: { Label(selecting ? "Practice selected" : "Practice list", systemImage: "rectangle.on.rectangle.angled") }
                        .buttonStyle(.borderedProminent).disabled(membershipLoading || practiceLoading || (selecting ? selectedIDs.isEmpty : visible.isEmpty))
                        .accessibilityIdentifier("vocabulary-practice-selection")
                }
            }.padding(14).background(Theme.paper)
        }.toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Add word", systemImage: "plus") { edited = nil; showEditor = true }.disabled(model.decks.isEmpty)
                    Button("Manage lists", systemImage: "folder") { showLists = true }
                    NavigationLink { LatinVocabularyView() } label: { Label("Latin Vocab", systemImage: "point.3.connected.trianglepath.dotted") }
                    Section("Create a text from this list") {
                        ForEach(VocabularyLanguageGroup.grouped(scoped)) { group in
                            NavigationLink(Theme.language(group.languageCode)) {
                                VocabularyLanguageGroupView(group: group, deckID: deckID, deckName: deckName)
                            }
                        }
                    }
                } label: { Label("List actions", systemImage: "ellipsis.circle") }
            }
        }
    }
    private func row(_ item: VocabularyItem) -> some View {
        HStack(spacing: 12) {
            if selecting {
                Button { if !selectedIDs.insert(item.id).inserted { selectedIDs.remove(item.id) } } label: {
                    Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(Theme.forest).frame(width: 36, height: 44)
                }.buttonStyle(.borderless).accessibilityLabel("Select \(item.draft.targetSurface)")
            }
            VStack(alignment: .leading, spacing: 5) {
                SemiticOrLatinVocabularyText(text: item.draft.targetSurface, language: item.draft.targetLanguage)
                    .font(.headline).foregroundStyle(Theme.forest)
                Text(item.draft.englishLemma).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(item.draft.targetLanguage.uppercased()).font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(Theme.forest.opacity(0.08), in: Capsule()).foregroundStyle(Theme.forest)
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
    @ViewBuilder private var detail: some View {
        if let word = currentWord {
            VocabularyWordDetailView(word: word, edit: { edited = word; showEditor = true }, practice: { practice([word.id]) })
                .id(word.id)
        } else {
            ContentUnavailableView("Choose a word", systemImage: "book.pages", description: Text("Select a word to see its meaning, examples and dictionary entry."))
        }
    }
    @ViewBuilder private func wordActions(_ item: VocabularyItem) -> some View {
        Button("Edit word") { edited = item; showEditor = true }
        Button("Practice this word") { practice([item.id]) }
        if !deckID.isEmpty { Button("Remove from list") { remove(item) } }
        Button("Delete word", role: .destructive) { deleteItem = item }
    }
    private func resetSelection() {
        selectedIDs = []; selectedWordID = nil
        #if os(iOS)
        compactColumn = .sidebar
        #endif
    }
    private func remove(_ item: VocabularyItem) {
        Task {
            await model.perform { try await $0.removeVocabulary(id: item.id, fromDeck: deckID) }
            await loadMemberships()
            if !memberIDs.contains(item.id) { selectedIDs.remove(item.id); if selectedWordID == item.id { selectedWordID = nil } }
        }
    }
    private func loadMemberships() async {
        guard !deckID.isEmpty, let db = model.database else { memberIDs = []; membershipLoading = false; return }
        let requested = deckID; membershipLoading = true
        defer { if requested == deckID { membershipLoading = false } }
        do {
            let words = try await db.vocabulary(deckID: requested)
            if deckID == requested { memberIDs = Set(words.map(\.id)); selectedIDs.formIntersection(memberIDs) }
        } catch { model.errorMessage = error.localizedDescription }
    }
    private func practice(_ ids: Set<String>) {
        guard !practiceLoading else { return }
        practiceLoading = true
        let requestedDeck = deckID
        Task {
            defer { practiceLoading = false }
            do {
                let cards = try await model.database?.practiceCards(deckID: requestedDeck.isEmpty ? nil : requestedDeck).filter { ids.contains($0.word.id) } ?? []
                guard !cards.isEmpty, deckID == requestedDeck else { return }
                #if os(macOS)
                model.reviewSession = ReviewPresentation(cards: cards.shuffled())
                #else
                review = VocabularyReviewPresentation(cards: cards.shuffled())
                #endif
            } catch { model.errorMessage = error.localizedDescription }
        }
    }
}
#if os(iOS)
private struct VocabularyReviewPresentation: Identifiable { let id = UUID(); let cards: [StudyCard] }
#endif

private struct VocabularyWordDetailView: View {
    @Environment(AppEnvironment.self) private var model
    let word: VocabularyItem
    let edit: () -> Void
    let practice: () -> Void
    @State private var meaning: String?
    @State private var dictionary = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Theme.language(word.draft.targetLanguage).uppercased()).font(.caption.weight(.semibold)).tracking(1)
                    SemiticOrLatinVocabularyText(text: word.draft.targetSurface, language: word.draft.targetLanguage, size: 36)
                    Text(word.draft.englishLemma).font(.title2)
                    Text(word.draft.partOfSpeech.capitalized).font(.subheadline).foregroundStyle(.secondary)
                    if word.draft.targetLemma != word.draft.targetSurface { Text("Dictionary form: " + word.draft.targetLemma).font(.subheadline) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                HStack(spacing: 12) {
                    Button("Dictionary", systemImage: "books.vertical") { dictionary = true }.buttonStyle(.borderedProminent)
                    Button("Practice", systemImage: "rectangle.on.rectangle.angled", action: practice).buttonStyle(.bordered)
                }
                if let meaning, !meaning.isEmpty, meaning != word.draft.englishLemma {
                    detailSection("Meaning", text: meaning)
                }
                if !word.draft.exampleEnglish.isEmpty { detailSection("English example", text: word.draft.exampleEnglish) }
                if !word.draft.exampleMixed.isEmpty { detailSection("Reading example", text: word.draft.exampleMixed) }
            }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Theme.paper).navigationTitle(word.draft.targetSurface)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit", systemImage: "pencil", action: edit) } }
            .task(id: word.id) { meaning = try? await model.dictionary?.meaning(for: word.draft) }
            .sheet(isPresented: $dictionary) { StudyWordDictionaryView(word: word.draft, dismissTitle: "Back to word").environment(model) }
    }
    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(Theme.forest)
            Text(text).font(.body).textSelection(.enabled).lineSpacing(5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VocabularyEditor: View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: VocabularyItem?
    let initialDeckID: String
    @State private var english = ""
    @State private var target = ""
    @State private var lemma = ""
    @State private var language = "de"
    @State private var sense = ""
    @State private var example = ""
    @State private var part = "noun"
    @State private var deck = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Expression") {
                    TextField("English expression", text: $english)
                    Picker("Language", selection: $language) { ForEach(model.languagePacks,id:\.languageCode) { Text($0.displayName).tag($0.languageCode) } }
                    TextField("Target expression", text: $target)
                    TextField("Dictionary form", text: $lemma)
                }
                Section {
                    TextField("Meaning, e.g. financial institution", text: $sense)
                    Picker("Part of speech", selection: $part) {
                        ForEach(["noun", "verb", "adjective", "adverb", "expression", "unspecified"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("English example (optional)", text: $example, axis: .vertical)
                } header: { Text("Context") } footer: { Text("A separate meaning keeps different uses of the same word apart.") }
                if item == nil {
                    Section("Save to") {
                        Picker("List", selection: $deck) { ForEach(model.decks) { Text($0.name).tag($0.id) } }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .autocorrectionDisabled()
            .navigationTitle(item == nil ? "New vocabulary" : "Edit vocabulary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving || english.isEmpty || target.isEmpty || sense.isEmpty) }
            }
            .interactiveDismissDisabled(saving)
            .onAppear {
                if let item {
                    let d = item.draft
                    english = d.englishLemma; target = d.targetSurface; lemma = d.targetLemma
                    language = d.targetLanguage; sense = d.senseID; example = d.exampleEnglish; part = d.partOfSpeech
                }
                deck = model.decks.contains(where: { $0.id == initialDeckID }) ? initialDeckID : model.decks.first?.id ?? ""
            }
        }
    }
    private func save() async {
        guard let db = model.database else { return }
        saving = true
        defer { saving = false }
        let draft = VocabularyDraft(englishLemma: english, targetLanguage: language, targetLemma: lemma.isEmpty ? target : lemma,
            targetSurface: target, senseID: sense, partOfSpeech: part, exampleEnglish: example, exampleMixed: item?.draft.exampleMixed ?? "",
            lexicalReference: item.flatMap { old in
                old.draft.targetLanguage==language && old.draft.targetLemma==(lemma.isEmpty ? target : lemma) && old.draft.targetSurface==target && old.draft.senseID==sense && old.draft.partOfSpeech==part ? old.draft.lexicalReference : nil
            })
        do {
            if let item { try await db.updateVocabulary(id: item.id, draft: draft) }
            else { _ = try await db.saveVocabulary(draft, inDeck: deck) }
            try await model.refresh(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct DeckManagerView: View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editingID: String?
    @State private var showName = false
    var body: some View {
        NavigationStack {
            List {
                if model.decks.isEmpty {
                    ContentUnavailableView("Make room for new words", systemImage: "folder.badge.plus",
                        description: Text("Create a list for a language, a topic, or a personal goal."))
                }
                ForEach(model.decks) { deck in
                    HStack { Label(deck.name, systemImage: "folder"); Spacer(); Text("\(deck.wordCount)").foregroundStyle(.secondary) }
                        .swipeActions {
                            Button("Delete list", role: .destructive) { Task { await model.perform { try await $0.deleteDeck(id: deck.id) } } }
                            Button("Rename") { editingID = deck.id; name = deck.name; showName = true }.tint(Theme.forest)
                        }
                }
                Section { Text("Deleting a list keeps its words in All vocabulary.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Your lists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("New list", systemImage: "folder.badge.plus") { editingID = nil; name = ""; showName = true } }
            }
            .alert(editingID == nil ? "New list" : "Rename list", isPresented: $showName) {
                TextField("List name", text: $name)
                Button("Save") {
                    let selected = editingID, value = name
                    Task { await model.perform { db in
                        if let selected { try await db.renameDeck(id: selected, name: value) }
                        else { _ = try await db.createDeck(name: value) }
                    } }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
