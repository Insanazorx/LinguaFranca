import SwiftUI

struct StudyView: View {
    @Environment(AppEnvironment.self) private var model
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Small steps,\nlasting words.").font(.system(.largeTitle, design: .serif))
                        Text("Build a vocabulary you can return to.").foregroundStyle(.secondary)
                    }.padding(.vertical, 18)
                }.listRowBackground(Color.clear)
                Section("Your library") {
                    LabeledContent("New cards", value: "\(model.summary?.newCards ?? 0)")
                    LabeledContent("Due for review", value: "\(model.summary?.dueCards ?? 0)")
                    LabeledContent("Reviews today", value: "\(model.summary?.reviewedToday ?? 0)")
                    LabeledContent("Daily target", value: "\(model.settings.dailyReviewTarget)")
                }
                Section("Study lists") {
                    ForEach(model.decks) { deck in
                        LabeledContent(deck.name, value: "\(deck.wordCount) words")
                    }
                    if model.decks.isEmpty { Text("Add a list in Vocabulary to get started.").foregroundStyle(.secondary) }
                }
                Section {
                    Text("Vocabulary collection is ready. Spaced repetition sessions are being added in the next development phase.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Study")
        }
    }
}
