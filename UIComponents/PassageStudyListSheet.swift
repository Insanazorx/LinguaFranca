import SwiftUI
import LinguaFrancaCore

struct PassageStudyListSheet:View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    let passage:GeneratedText
    @State private var destination="new"
    @State private var name=""
    @State private var count=0
    @State private var saving=false
    @State private var error:String?
    @State private var result:PassageVocabularyImport?
    var body:some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label("\(result.added) expressions added",systemImage:"checkmark.circle.fill")
                        if result.alreadyPresent>0 {Text("\(result.alreadyPresent) already in this list. Existing cards and review history were kept.").foregroundStyle(.secondary)}
                        Button("Done"){dismiss()}
                    }
                } else {
                    Section {
                        Text("Add all \(count) distinct translated expressions from this text. Each card keeps its original English sentence.")
                        Picker("Study list",selection:$destination) {
                            Text("Create a new list").tag("new")
                            ForEach(model.decks) {Text($0.name).tag($0.id)}
                        }
                        if destination=="new" {TextField("List name",text:$name)}
                        Button(saving ? "Adding expressions…":"Add all words",systemImage:"text.badge.plus") {Task {await save()}}
                            .disabled(saving || count==0 || (destination=="new" && name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
                            .accessibilityIdentifier("confirm-passage-words")
                        if saving {ProgressView()}
                    }
                }
                if let error {Section {Text(error).foregroundStyle(.red)}}
            }.navigationTitle("Words to study list")
                .toolbar {ToolbarItem(placement:.cancellationAction){Button("Close"){dismiss()}.disabled(saving)}}
                .task {
                    name=String((passage.metadata["title"] ?? passage.topic).prefix(70))
                    destination=model.decks.first?.id ?? "new"
                    do {count=try passage.studyVocabulary().count} catch {self.error=error.localizedDescription}
                }
        }
    }
    private func save() async {
        guard let database=model.database else {return}
        saving=true;defer {saving=false}
        do {
            result=try await database.addPassageVocabulary(passage,to:destination=="new" ? .new(name):.existing(destination))
            try await model.refresh()
        } catch {self.error=error.localizedDescription}
    }
}
