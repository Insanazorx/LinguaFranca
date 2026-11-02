import SwiftUI
import LinguaFrancaCore

struct CatalogPracticeLauncher: View {
    let source:CatalogPracticeSource
    var latinPair=LatinVocabularyPair.all
    var wordType=LatinVocabularyWordType.all
    var semiticPair=SemiticFamilyPair.all
    var query=""
    var body: some View {
        NavigationLink {
            CatalogPracticeHub(source:source,latinPair:latinPair,wordType:wordType,semiticPair:semiticPair,query:query)
        } label: {
            HStack(spacing:12) {
                Image(systemName:"sparkles.rectangle.stack.fill").font(.title2)
                VStack(alignment:.leading,spacing:4) {
                    Text("Shuffle & practice").font(.headline)
                    Text("Small random sets · context clues · combos").font(.caption).foregroundStyle(.secondary)
                }
            }.foregroundStyle(Theme.forest).padding(.vertical,8)
        }.accessibilityIdentifier(source.rawValue+"-practice-launcher")
    }
}
private struct CatalogRoundPresentation: Identifiable {
    var id:String { start.score.sessionID }
    let start:CatalogPracticeStart
    let useContext:Bool
}
private struct CatalogPracticeHub: View {
    @Environment(AppEnvironment.self) private var model
    let source:CatalogPracticeSource
    let latinPair:LatinVocabularyPair
    let wordType:LatinVocabularyWordType
    let semiticPair:SemiticFamilyPair
    let query:String
    @State private var familyCount=8
    @AppStorage("catalogPractice.context") private var context=true
    @State private var stats:CatalogPracticeStats?
    @State private var presentation:CatalogRoundPresentation?
    @State private var loading=false
    @State private var error:String?
    var body: some View {
        Form {
            Section {
                Label(source == .latin ? "Latin Vocab practice" : "Semitic Roots practice",systemImage:"sparkles.rectangle.stack.fill").font(.title2).foregroundStyle(Theme.forest)
                Text("Guess the meaning, tap to reveal, then swipe right if you recalled it or left to learn it again. Keep a combo going; context cards earn a small bonus.")
                Text(source == .latin ? latinPair.title+" · "+wordType.title : semiticPair.title).font(.subheadline).foregroundStyle(.secondary)
                if !query.isEmpty {Text("Current search: "+query).font(.footnote)}
            }
            Section("Your next mini-set") {
                Picker("Families",selection:$familyCount) {Text("8 · quick").tag(8);Text("12 · explore").tag(12);Text("20 · long").tag(20)}
                Toggle("Occasional context cards",isOn:$context)
                Text("New words mix with due families. Each language keeps its own meanings. Your selection repeats until you choose Exit; shuffle again for another set.").font(.footnote).foregroundStyle(.secondary)
                Button {Task {await start()}} label: {Label(loading ? "Preparing…" : "Start shuffled set",systemImage:"shuffle")}
                    .buttonStyle(.borderedProminent).tint(Theme.forest).disabled(loading)
                    .accessibilityIdentifier("catalog-start")
                if loading {ProgressView()}
                if let error {Text(error).foregroundStyle(.red)}
            }
            if let stats {
                Section("Your progress") {
                    LabeledContent("Total recall points",value:stats.points.formatted())
                    LabeledContent("Answers",value:stats.answers.formatted())
                    LabeledContent("Best combo",value:"\(stats.bestCombo)×")
                    LabeledContent("Best session",value:stats.bestRound.formatted())
                }
            }
            Section {
                Text("Recall is self-rated, like a flashcard review. Scheduling uses FSRS 6. Scores and memory history stay on this device, separate from your saved study lists.")
                Text("Context sentences are authored English learning clues, not quotations or demonstrations of complete target-language grammar. A card appears in context only when a matching dictionary sense is available.")
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Practice")
            .task {await refreshStats()}
            #if os(iOS)
            .fullScreenCover(item:$presentation,onDismiss:{Task {await refreshStats()}}) {round in CatalogPracticeSessionView(start:round.start,useContext:round.useContext)}
            #else
            .sheet(item:$presentation,onDismiss:{Task {await refreshStats()}}) {round in CatalogPracticeSessionView(start:round.start,useContext:round.useContext).frame(minWidth:650,minHeight:760)}
            #endif
    }
    private func refreshStats() async {do {stats=try await model.database?.catalogStats(source:source)} catch {self.error=error.localizedDescription}}
    private func start() async {
        guard !loading,let db=model.database else {return}
        loading=true;error=nil;defer {loading=false}
        do {
            let due=try await db.dueCatalogQuestions(source:source)
            let seed=UInt64.random(in:0...UInt64.max)
            var questions:[CatalogQuestion]
            if source == .latin, let catalog=model.latinVocabulary {
                questions=try await catalog.practiceQuestions(query:query,pair:latinPair,wordType:wordType,families:familyCount,preferred:due.map(\.familyID),seed:seed)
            } else if source == .semitic,let lexicon=model.semiticLexicon,let catalog=lexicon.families {
                questions=try await catalog.practiceQuestions(lexicon:lexicon,query:query,pair:semiticPair,families:familyCount,preferred:due.map(\.familyID),seed:seed)
            } else {throw DomainError.missingRecord}
            // Revisit the actual due sense, rather than a new random word from its family.
            let chosen=Set(questions.map(\.familyID))
            let languages=source == .latin ? latinPair.languages : semiticPair.languages
            let revisits=due.filter {chosen.contains($0.familyID) && (languages.isEmpty || languages.contains($0.language)) && (source != .latin || wordType == .all || $0.partOfSpeech==wordType.rawValue)}
            let dueKeys=Set(revisits.map{$0.familyID+":"+$0.language})
            questions=Array(revisits.prefix(50))+questions.filter{!dueKeys.contains($0.familyID+":"+$0.language)}
            var seen=Set<String>();questions=Array(questions.filter{seen.insert($0.id).inserted}.prefix(100))
            presentation = .init(start:try await db.startCatalogPractice(questions,source:source),useContext:context)
        } catch {self.error=error.localizedDescription}
    }
}

private struct CatalogPracticeSessionView: View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var queue:CatalogPracticeQueue
    @State private var score:CatalogScore
    @State private var flipped=false
    @State private var drag=CGSize.zero
    @State private var saving=false
    @State private var error:String?
    @State private var inspection:DictionaryRecord?
    let useContext:Bool
    private let ink=Color(red:0.08,green:0.12,blue:0.14)
    private let colors:[Color]=[Color(red:0.98,green:0.83,blue:0.35),Color(red:0.53,green:0.83,blue:0.62),Color(red:0.55,green:0.75,blue:0.95),Color(red:0.97,green:0.57,blue:0.54)]
    init(start:CatalogPracticeStart,useContext:Bool) {
        _queue=State(initialValue:CatalogPracticeQueue(cards:start.cards));_score=State(initialValue:start.score);self.useContext=useContext
    }
    private var showsContext:Bool {useContext && queue.current?.question.context != nil && (queue.reviews/max(1,queue.count))%2==0}
    var body: some View {
        GeometryReader {g in
            let width=max(1,min(g.size.width-40,(g.size.height-180)*0.67,490))
            VStack(spacing:12) {
                HStack {
                    Label(score.points.formatted(),systemImage:"sparkles")
                    Spacer();Text("\(score.combo)× combo").bold()
                    Spacer();Button("Exit") {Task {await exit()}}.disabled(saving).accessibilityIdentifier("catalog-exit")
                }.foregroundStyle(.white).padding(.horizontal,24).padding(.top,12)
                Text("\(queue.count) words · \(score.answers) answers · best \(score.bestCombo)×").font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength:0)
                ZStack {
                    RoundedRectangle(cornerRadius:28).fill(colors[(queue.reviews+1)%4]).frame(width:width,height:width*1.5).rotationEffect(.degrees(3)).offset(x:5,y:10).accessibilityHidden(true)
                    if let question=queue.current?.question {
                        ScrollView {
                            VStack(spacing:20) {
                                Text(Theme.language(question.language)).font(.caption.bold()).textCase(.uppercase)
                                if flipped {
                                    Button {inspection=question.dictionaryRecord} label: {nativeWord(question).underline()}.buttonStyle(.plain).accessibilityIdentifier("catalog-dictionary")
                                    if !question.transliteration.isEmpty {Text(question.transliteration).font(.subheadline)}
                                    Text(question.meaning).font(.title3).textSelection(.enabled)
                                    if showsContext,let context=question.context {Text(context.original).font(.subheadline).italic()}
                                    Text([question.partOfSpeech,question.pattern].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption)
                                    Divider()
                                    Text(question.familyTitle).font(.headline)
                                    ForEach(Array(question.peers.enumerated()),id:\.offset) {_,peer in
                                        VStack(spacing:3) {Text(peer.language.uppercased()+" · "+peer.word).font(.headline);Text(peer.meaning).font(.caption).lineLimit(3)}
                                    }
                                    Text("Tap the word to inspect its dictionary entry.").font(.caption)
                                } else if showsContext,let context=question.context {
                                    Text("Context clue").font(.caption)
                                    (Text(context.before)+Text("\u{2067}"+question.word+"\u{2069}").bold().underline()+Text(context.after)).font(.title2).environment(\.layoutDirection,.leftToRight)
                                    Text("What does the marked word mean?").font(.subheadline)
                                } else {
                                    nativeWord(question)
                                    Text("What does this word mean?").font(.subheadline)
                                }
                                if !flipped {Text("Tap to reveal").font(.caption).opacity(0.7)}
                            }.multilineTextAlignment(.center).frame(maxWidth:.infinity,minHeight:width*1.5-56).padding(28)
                        }.id(question.id + (flipped ? ":back" : ":front")).frame(width:width,height:width*1.5)
                            .background(colors[queue.reviews%4],in:RoundedRectangle(cornerRadius:28))
                            .overlay(alignment:.topTrailing) {if abs(drag.width)>40 {Text(drag.width>0 ? "RECALLED" : "LEARN AGAIN").font(.caption.bold()).padding(16).allowsHitTesting(false)}}
                            .foregroundStyle(ink).shadow(radius:12,y:8).offset(drag).rotationEffect(.degrees(Double(drag.width)/30))
                            .contentShape(RoundedRectangle(cornerRadius:28))
                            .onTapGesture {if !saving {withAnimation(.easeInOut(duration:0.2)) {flipped.toggle()}}}
                            .simultaneousGesture(DragGesture(minimumDistance:12).onChanged{if !saving {drag=$0.translation}}.onEnded {value in
                                guard !saving else {return}
                                if flipped,let rating=CardDragDecision.rating(x:value.translation.width,y:value.translation.height,cardWidth:width) {Task {await rate(rating)}}
                                else {withAnimation(.spring()) {drag = .zero}}
                            })
                            .accessibilityIdentifier("catalog-card")
                            .accessibilityAction(named:"Reveal meaning") {flipped=true}
                    }
                }
                Spacer(minLength:0)
                HStack(spacing:20) {
                    Button("Not yet") {Task {await rate(.again)}}
                    Button(flipped ? "Recalled" : "Reveal") {if flipped {Task {await rate(.good)}} else {flipped=true}}
                }.buttonStyle(.borderedProminent).tint(.white.opacity(0.18)).foregroundStyle(.white).disabled(saving)
                    .accessibilityIdentifier("catalog-answer-actions")
                if let error {Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal)}
                Text("Self-rated recall · right: know · left: learn again").font(.caption2).foregroundStyle(.white.opacity(0.65)).padding(.bottom,14)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.background(Color(white:0.055).ignoresSafeArea())
            .interactiveDismissDisabled(true)
            .sheet(item:$inspection) {record in NavigationStack {DictionaryEntryView(record:record).toolbar {ToolbarItem(placement:.confirmationAction) {Button("Back to practice") {inspection=nil}}}}}
    }
    private func nativeWord(_ question:CatalogQuestion) -> some View {
        Text(question.word).font(question.language=="syc" ? .custom("NotoSansSyriac-Regular",size:38) : .system(size:38,weight:.semibold))
            .environment(\.layoutDirection,SemiticUnicode.isRightToLeft(question.language) ? .rightToLeft : .leftToRight)
    }
    private func rate(_ rating:ReviewRating) async {
        guard !saving else {return}
        guard flipped else {flipped=true;drag = .zero;return}
        guard let current=queue.current,let db=model.database else {return}
        saving=true;error=nil;defer {saving=false}
        do {
            let result=try await db.reviewCatalogCard(current.card,question:current.question,sessionID:score.sessionID,rating:rating,usedContext:showsContext)
            try queue.record(result.card);score=result.score;flipped=false;drag = .zero
        } catch {self.error=error.localizedDescription;drag = .zero}
    }
    private func exit() async {
        guard !saving else {return};saving=true
        do {try await model.database?.endCatalogPractice(sessionID:score.sessionID);dismiss()}
        catch {self.error=error.localizedDescription;saving=false}
    }
}
