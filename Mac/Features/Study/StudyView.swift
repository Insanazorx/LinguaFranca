import SwiftUI
import LinguaFrancaCore

struct StudyView: View {
    @Environment(AppEnvironment.self) private var model
    @State private var deckID=""
    @State private var cards:[StudyCard]=[]
    @State private var loading=false
    var body:some View {
        NavigationStack {
            List {
                Section {
                    Text("Your words.\nYour pace.").font(.system(.largeTitle,design:.serif)).padding(.vertical,12)
                    Text("Choose a list and practice whenever you like.").foregroundStyle(.secondary)
                    Picker("Study list",selection:$deckID) {
                        Text("All vocabulary").tag("")
                        ForEach(model.decks) { Text($0.name).tag($0.id) }
                    }
                }
                Section {
                    Button { model.reviewSession=ReviewPresentation(cards:cards.shuffled()) } label: {
                        Label("Practice \(cards.count) words",systemImage:"rectangle.on.rectangle.angled")
                            .frame(maxWidth:.infinity).padding(.vertical,10)
                    }.disabled(loading || cards.isEmpty).accessibilityIdentifier("start-review")
                    Text("Practice continues until you exit. Due cards come first; early repeats keep the list going.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Choose individual words") {PracticeWordListView(deckID:deckID,forgottenOnly:false)}
                    NavigationLink {
                        PracticeWordListView(deckID:deckID,forgottenOnly:true)
                    } label: {
                        HStack { Label("Forgotten words",systemImage:"arrow.counterclockwise");Spacer();Text("\(cards.filter { $0.card.progress == .forgotten }.count)").foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("forgotten-words")
                }
                if cards.isEmpty && !loading {
                    ContentUnavailableView("Collect words to practice",systemImage:"rectangle.on.rectangle",description:Text("Save words from a reading or the dictionary to a study list."))
                }
                Section { Text("Tap to turn a card. Hold and move it in any direction. Release to the right: I know. Release to the left: I don't know.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Study")
                .onAppear { deckID = model.studyDeckID }
                .onChange(of: deckID) { _, value in model.studyDeckID = value }
                .task(id:deckID) { await load() }
                .onChange(of:model.vocabulary) { _,_ in Task { await load() } }
                .onChange(of:model.decks) { _,decks in if !deckID.isEmpty && !decks.contains(where:{$0.id==deckID}) { deckID="" } }
        }
    }
    private func load() async {
        guard let db=model.database else {return}
        let selected=deckID;loading=true;defer{loading=false}
        do { let fetched=try await db.practiceCards(deckID:selected.isEmpty ? nil : selected);if selected==deckID {cards=fetched} }
        catch {model.errorMessage=error.localizedDescription}
    }
}

struct ReviewPresentation:Identifiable { let id=UUID();let cards:[StudyCard] }

private struct PracticeWordListView:View {
    @Environment(AppEnvironment.self) private var model
    let deckID:String
    let forgottenOnly:Bool
    @State private var query=""
    @State private var cards:[StudyCard]=[]
    private var visible:[StudyCard] {cards.filter {query.isEmpty || OfflineDictionary.key($0.word.draft.targetSurface+" "+$0.word.draft.englishLemma).contains(OfflineDictionary.key(query))}}
    var body:some View {
        List {
            if cards.isEmpty { ContentUnavailableView(forgottenOnly ? "Nothing forgotten":"No saved words",systemImage:"checkmark",description:Text(forgottenOnly ? "Words you mark as unfamiliar will appear here.":"Save a word to a study list to begin.")) }
            else {
                Section {
                    Button("Practice these \(visible.count) words",systemImage:"rectangle.on.rectangle.angled") { model.reviewSession=ReviewPresentation(cards:visible.shuffled()) }.disabled(visible.isEmpty)
                        .accessibilityIdentifier("practice-forgotten")
                }
                ForEach(visible) { card in
                    HStack {
                    NavigationLink { WordInformationView(word:card.word) } label: {
                        VStack(alignment:.leading,spacing:5) {
                            SemiticOrLatinVocabularyText(text:card.word.draft.targetSurface,language:card.word.draft.targetLanguage).foregroundStyle(Theme.accent(card.word.draft.targetLanguage))
                            Text(card.word.draft.englishLemma).font(.subheadline)
                            Text(Theme.language(card.word.draft.targetLanguage)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,5)
                    }.contextMenu { Button("Practice this word") {model.reviewSession=ReviewPresentation(cards:[card])} }
                    Button {model.reviewSession=ReviewPresentation(cards:[card])} label:{Image(systemName:"play.circle").imageScale(.large)}
                        .buttonStyle(.borderless).accessibilityLabel("Practice \(card.word.draft.targetSurface)")
                    }
                }
            }
        }.navigationTitle(forgottenOnly ? "Forgotten words":"Choose words")
            .searchable(text:$query,prompt:"Find a saved word")
            .task {await load()}
            .onChange(of:model.vocabulary) {_,_ in Task{await load()}}
    }
    private func load() async {
        do {cards=try await model.database?.practiceCards(deckID:deckID.isEmpty ? nil : deckID,forgottenOnly:forgottenOnly) ?? []}
        catch {model.errorMessage=error.localizedDescription}
    }
}

struct WordInformationView:View {
    @Environment(AppEnvironment.self) private var model
    let word:VocabularyItem
    @State private var meaning:String?
    var body:some View {
        List {
            Section {
                SemiticOrLatinVocabularyText(text:word.draft.targetSurface,language:word.draft.targetLanguage).font(.title)
                Text(word.draft.englishLemma).font(.title2).textSelection(.enabled)
                if let meaning,!meaning.isEmpty,meaning != word.draft.englishLemma {Text(meaning).textSelection(.enabled)}
                Text("\(Theme.language(word.draft.targetLanguage)) · \(word.draft.partOfSpeech.capitalized)").foregroundStyle(.secondary)
                if word.draft.targetLemma != word.draft.targetSurface {Text(word.draft.targetLemma)}
            }
            if !word.draft.exampleEnglish.isEmpty {Section("English example"){Text(word.draft.exampleEnglish).textSelection(.enabled)}}
            if !word.draft.exampleMixed.isEmpty {Section("Reading example"){Text(word.draft.exampleMixed).textSelection(.enabled)}}
        }.navigationTitle("Word details").inlineNavigationTitle()
            .task(id:word.id) {meaning=try? await model.dictionary?.meaning(for:word.draft)}
    }
}
