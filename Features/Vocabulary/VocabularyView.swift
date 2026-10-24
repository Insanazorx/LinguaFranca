import SwiftUI
import LinguaFrancaCore

struct VocabularyView: View {
    @Environment(AppEnvironment.self) private var model
    @State private var query = ""
    @State private var deckID = ""
    @State private var showEditor = false
    @State private var edited: VocabularyItem?
    @State private var showLists = false
    @State private var deleteItem: VocabularyItem?
    var filtered: [VocabularyItem] {
        model.vocabulary.filter {
            query.isEmpty || [$0.draft.englishLemma, $0.draft.targetSurface, $0.draft.senseID, $0.draft.exampleEnglish]
                .contains(where: { $0.localizedStandardContains(query) })
        }
    }
    @State private var memberIDs: Set<String> = []
    var visible: [VocabularyItem] { deckID.isEmpty ? filtered : filtered.filter { memberIDs.contains($0.id) } }
    private var languageGroups: [VocabularyLanguageGroup] {
        let current = deckID.isEmpty ? model.vocabulary : model.vocabulary.filter { memberIDs.contains($0.id) }
        let matching = Set(visible.map(\.id))
        return VocabularyLanguageGroup.grouped(current).filter { $0.items.contains { matching.contains($0.id) } }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("List", selection: $deckID) {
                        Text("All vocabulary").tag("")
                        ForEach(model.decks) { Text("\($0.name) (\($0.wordCount))").tag($0.id) }
                    }
                    Button("Manage lists", systemImage: "folder") { showLists = true }
                }
                if visible.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Collect words that matter" : "No matching words", systemImage: "character.book.closed",
                        description: Text(query.isEmpty ? "Create a list and add your first expression." : "Try another expression or meaning."))
                        .listRowBackground(Color.clear)
                }
                ForEach(languageGroups) { group in
                    NavigationLink {
                        VocabularyLanguageGroupView(group: group, deckID: deckID, deckName: model.decks.first { $0.id == deckID }?.name ?? "All vocabulary")
                            .environment(model)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(Theme.language(group.languageCode)).font(.headline)
                                Spacer()
                                Text("\(group.items.count) words").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(group.items.prefix(4).map { $0.draft.targetSurface }.joined(separator: " · "))
                                .lineLimit(2).font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("vocabulary-group-" + group.languageCode)
                }
            }
            .navigationTitle("Vocabulary").searchable(text: $query, prompt: "Expression or meaning")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add word", systemImage: "plus") { edited = nil; showEditor = true }
                        .disabled(model.decks.isEmpty)
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: { Task { await loadMemberships() } }) {
                VocabularyEditor(item: edited, initialDeckID: deckID).environment(model)
            }
            .sheet(isPresented: $showLists) { DeckManagerView().environment(model) }
            .task(id: deckID) { await loadMemberships() }
            .onChange(of: model.decks) { _, decks in
                if !deckID.isEmpty && !decks.contains(where: { $0.id == deckID }) { deckID = "" }
            }
            .alert("Delete this word?", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } })) {
                Button("Delete", role: .destructive) {
                    if let item = deleteItem { Task { await model.perform { try await $0.deleteVocabulary(id: item.id) } } }
                    deleteItem = nil
                }
                Button("Cancel", role: .cancel) { deleteItem = nil }
            } message: { Text("This removes it from every list and deletes its study history.") }
        }
    }
    private func loadMemberships() async {
        guard !deckID.isEmpty, let db = model.database else { memberIDs = []; return }
        let requested = deckID
        do {
            let words = try await db.vocabulary(deckID: requested)
            if deckID == requested { memberIDs = Set(words.map(\.id)) }
        } catch { model.errorMessage = error.localizedDescription }
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
                    Picker("Language", selection: $language) { Text("German").tag("de"); Text("Russian").tag("ru") }
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
            targetSurface: target, senseID: sense, partOfSpeech: part, exampleEnglish: example, exampleMixed: item?.draft.exampleMixed ?? "")
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
                ToolbarItem(placement: .primaryAction) { Button("New list", systemImage: "folder.badge.plus") { editingID = nil; name = ""; showName = true } }
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
