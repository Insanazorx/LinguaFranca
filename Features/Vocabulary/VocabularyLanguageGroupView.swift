import SwiftUI
import LinguaFrancaCore

struct VocabularyLanguageGroupView: View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let group: VocabularyLanguageGroup
    let deckID: String
    let deckName: String
    @State private var edited: VocabularyItem?
    @State private var deleteItem: VocabularyItem?
    @State private var removedIDs: Set<String> = []
    private var items: [VocabularyItem] {
        let originalIDs = Set(group.items.map(\.id))
        return model.vocabulary.filter { originalIDs.contains($0.id) && !removedIDs.contains($0.id) && $0.draft.targetLanguage == group.languageCode }
    }
    private var groupID: String { deckID + ":" + group.languageCode }
    private var readings: [VocabularyPracticeReading] { model.vocabularyReadings.filter { $0.groupID == groupID } }
    var body: some View {
        List {
            Section {
                Button {
                    model.generateVocabulary(items: items, languageCode: group.languageCode, groupID: groupID)
                } label: {
                    Label("Bu kelimelerle tamamen hedef dilde metin oluştur", systemImage: "sparkles")
                        .padding(.vertical, 6)
                }.disabled(model.generating || items.isEmpty || !model.canGenerate)
                    .accessibilityIdentifier("generate-vocabulary-text")
                Text("All \(items.count) words · \(Theme.language(group.languageCode)) only · Up to 3 words per short text. Dictionary-verified inflections count too. Every expression is checked before a text is shown. Readings last for this app session.")
                    .font(.footnote).foregroundStyle(.secondary)
                if model.activeVocabularyGroup == groupID {
                    HStack {
                        ProgressView()
                        Text("Writing \(model.vocabularyBatchProgress + 1) / \(max(1, model.vocabularyBatchTotal))…")
                        Spacer()
                        Button("Cancel") { model.cancelGeneration() }
                    }
                }
            } header: { Text(deckName) }
            if !readings.isEmpty {
                Section("This session · \(Theme.language(group.languageCode))") {
                    ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Text \(index+1) · \(reading.expressionIDs.count) expressions").font(.caption).foregroundStyle(.secondary)
                            Text(reading.text).font(.system(.body, design: .serif)).lineSpacing(5).textSelection(.enabled)

                        }.padding(.vertical, 8)
                    }
                }
            }
            Section("Words · \(items.count)") {
                ForEach(items) { item in
                    Button { edited = item } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.draft.targetSurface).font(.title3).foregroundStyle(group.languageCode == "de" ? Theme.german : Theme.russian)
                            Text(item.draft.englishLemma).foregroundStyle(.primary)
                            Text(item.draft.senseID).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleteItem = item }
                        if !deckID.isEmpty {
                            Button("Remove from list") {
                                Task {
                                    await model.perform { try await $0.removeVocabulary(id: item.id, fromDeck: deckID) }
                                    // Confirm removal through a read, rather than hiding a failed write.
                                    if let db = model.database, let members = try? await db.vocabulary(deckID: deckID), !members.contains(where: { $0.id == item.id }) { removedIDs.insert(item.id) }
                                }
                            }.tint(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle(Theme.language(group.languageCode))
        .sheet(item: $edited) { VocabularyEditor(item: $0, initialDeckID: deckID).environment(model) }
        .alert("Delete this word?", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } })) {
            Button("Delete", role: .destructive) {
                if let item = deleteItem { Task { await model.perform { try await $0.deleteVocabulary(id: item.id) } } }
                deleteItem = nil
            }
            Button("Cancel", role: .cancel) { deleteItem = nil }
        } message: { Text("This removes it from every list and deletes its study history.") }
    }
}
