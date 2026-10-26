import SwiftUI
import LinguaFrancaCore

struct ReviewSessionView: View {
    @Environment(AppEnvironment.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: ContinuousStudySession
    let onExit: (() -> Void)?
    @State private var flipped = false
    @State private var inspection:CardDictionarySelection?
    @State private var inspectionStarted:Date?
    @State private var drag = CGSize.zero
    @GestureState private var held = false
    @FocusState private var focused: Bool
    @State private var saving = false
    @State private var error: String?
    @State private var shownAt = Date.now
    @State private var meaning: String?
    @State private var tint:CardTint
    @State private var nextTint:CardTint
    private let ink = Color(red: 0.08, green: 0.12, blue: 0.14)

    init(cards: [StudyCard], onExit: (() -> Void)? = nil) {
        _session = State(initialValue: ContinuousStudySession(cards: cards))
        let first=CardTint.allCases.randomElement()!
        _tint=State(initialValue:first)
        _nextTint=State(initialValue:CardTint.allCases.filter{$0 != first}.randomElement()!)
        self.onExit = onExit
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, min(geometry.size.width - 48, (geometry.size.height - 64) * 2 / 3, 520))
            let lift=min(1,abs(drag.width)/max(1,width*0.8))
            ZStack {
                Color(white: 0.055).ignoresSafeArea()
                if session.count>1,session.current != nil {
                    // One closed backing card. No future card faces, dictionary lookups
                    // or vocabulary views are created for the rest of the selection.
                    RoundedRectangle(cornerRadius:30)
                        .fill(nextTint.color)
                        .overlay {RoundedRectangle(cornerRadius:30).strokeBorder(.white.opacity(0.3),lineWidth:1)}
                        .frame(width:width,height:width*1.5)
                        .scaleEffect(0.97+0.03*lift)
                        .rotationEffect(.degrees(2.2*(1-lift)))
                        .offset(x:6*(1-lift),y:14*(1-lift))
                        .shadow(color:.black.opacity(0.3),radius:10,y:8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                ZStack {
                    if let current = session.current {
                        let word = current.word.draft
                        face(word, back: false).opacity(flipped ? 0 : 1)
                            .rotation3DEffect(.degrees(flipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                        face(word, back: true).opacity(flipped ? 1 : 0)
                            .rotation3DEffect(.degrees(flipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    } else {
                        Text("This selection has no words left.").font(.title2).multilineTextAlignment(.center).padding(32)
                    }
                }
                .frame(width: width, height: width * 1.5)
                .background(tint.color, in: RoundedRectangle(cornerRadius: 30))
                .overlay {RoundedRectangle(cornerRadius:30).strokeBorder(.white.opacity(0.22),lineWidth:1).allowsHitTesting(false)}
                .overlay(alignment: .topLeading) {
                    if abs(drag.width) > 35 {
                        Text(drag.width > 0 ? "I KNOW" : "DON'T KNOW").font(.caption.bold()).padding(22)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { exit() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).padding(8).disabled(saving)
                    .accessibilityLabel("Exit practice").accessibilityIdentifier("exit-review")
                    .keyboardShortcut(.cancelAction)
                }
                .overlay(alignment: .bottom) {
                    if let error {
                        Text(error).font(.footnote).multilineTextAlignment(.center).padding(16)
                            .background(tint.color, in: RoundedRectangle(cornerRadius: 20)).padding(8)
                    }
                }
                .shadow(color: .black.opacity(held ? 0.4 : 0.22), radius: held ? 26 : 12, y: held ? 14 : 6)
                .scaleEffect(held ? 1.02 : 1)
                .animation(.easeOut(duration: 0.12), value: held)
                .offset(drag)
                .rotationEffect(.degrees(max(-12, min(12, Double(drag.width) / 30))))
                .contentShape(RoundedRectangle(cornerRadius: 30))
                .onTapGesture { flip() }
                .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .updating($held) { _, state, _ in if !saving { state = true } }
                    .onChanged { value in if !saving { drag = value.translation } }
                    .onEnded { value in
                        guard !saving else { return }
                        if let rating = CardDragDecision.rating(x: value.translation.width, y: value.translation.height, cardWidth: width) {
                            Task { await rate(rating, width: width) }
                        } else { recenter() }
                    })
                .onChange(of: held) { _, active in if !active && !saving { recenter() } }
                .task(id: session.current?.id) {
                    meaning = nil
                    guard let current = session.current else { return }
                    let fetched = try? await model.dictionary?.meaning(for: current.word.draft)
                    if !Task.isCancelled && session.current?.id == current.id { meaning = fetched }
                }
                .accessibilityIdentifier("review-card")
                .accessibilityAction(named: "Flip card") { flip() }
                .accessibilityAction(named: "I know it") { Task { await rate(.good, width: width) } }
                .accessibilityAction(named: "I don't know it") { Task { await rate(.again, width: width) } }
                .contextMenu {
                    Button("Again") { Task { await rate(.again, width: width) } }
                    Button("Hard") { Task { await rate(.hard, width: width) } }
                    Button("Good") { Task { await rate(.good, width: width) } }
                    Button("Easy") { Task { await rate(.easy, width: width) } }
                }
                .focusable().focusEffectDisabled().focused($focused)
                .onKeyPress(.space) { flip(); return .handled }
                .onKeyPress(.leftArrow) { Task { await rate(.again, width: width) }; return .handled }
                .onKeyPress(.rightArrow) { Task { await rate(.good, width: width) }; return .handled }
                .onKeyPress(characters: CharacterSet(charactersIn: "1234"), phases: .down) { press in
                    guard let value = Int(press.characters), let rating = ReviewRating(rawValue: value) else { return .ignored }
                    Task { await rate(rating, width: width) }; return .handled
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(ink)
        }
        .sheet(item:$inspection,onDismiss:{
            if let started=inspectionStarted {shownAt=shownAt.addingTimeInterval(max(0,Date.now.timeIntervalSince(started)))}
            inspectionStarted=nil;focused=true
        }) {selection in StudyWordDictionaryView(word:selection.word)}
        .interactiveDismissDisabled(true)
        .onAppear { focused = true }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
    }

    private func face(_ word: VocabularyDraft, back: Bool) -> some View {
        VStack(spacing: 16) {
            Text(Theme.language(word.targetLanguage).uppercased()).font(.caption.weight(.semibold)).tracking(1.5).opacity(0.65)
            if back {
                Button {openDictionary(word)} label: {
                    SemiticOrLatinVocabularyText(text:word.targetSurface,language:word.targetLanguage,size:42)
                        .lineLimit(3).minimumScaleFactor(0.55)
                }.buttonStyle(.plain).disabled(!flipped || saving)
                    .accessibilityLabel("Inspect \(word.targetSurface) in dictionary")
                    .accessibilityIdentifier("card-dictionary-word")
            } else {
                SemiticOrLatinVocabularyText(text:word.targetSurface,language:word.targetLanguage,size:42)
                    .lineLimit(3).minimumScaleFactor(0.55)
            }
            if back {
                Divider().overlay(ink.opacity(0.2))
                Text(word.englishLemma).font(.title2.weight(.medium)).lineLimit(3).accessibilityIdentifier("card-meaning")
                Text(word.partOfSpeech.capitalized).font(.subheadline).opacity(0.65)
                if let meaning, !meaning.isEmpty, meaning != word.englishLemma {
                    Text(meaning).font(.body).lineLimit(5)
                }
                if !word.exampleEnglish.isEmpty { Text(word.exampleEnglish).font(.subheadline).italic().lineLimit(4).opacity(0.8) }
            } else {
                Text("Tap to reveal").font(.footnote).opacity(0.6)
            }
        }
        .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.vertical, 62)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(back != flipped)
        .allowsHitTesting(back == flipped)
    }

    private func openDictionary(_ word:VocabularyDraft) {
        guard flipped,!saving,inspection==nil else {return}
        drag = .zero;focused=false;inspectionStarted = .now
        inspection=CardDictionarySelection(word:word)
    }
    private func flip() {
        guard !saving, inspection==nil, session.current != nil else { return }
        focused = true
        withAnimation(.easeInOut(duration: 0.25)) { flipped.toggle() }
    }
    private func recenter() { withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { drag = .zero } }
    private func exit() {
        guard !saving,inspection==nil else { return }
        if let onExit { onExit() } else { dismiss() }
    }
    private func rate(_ rating: ReviewRating, width: CGFloat) async {
        guard !saving, inspection==nil, let current = session.current, let db = model.database else { return }
        saving = true; error = nil
        defer { saving = false }
        let now = Date.now
        do {
            let updated = try await db.reviewCard(current.card, rating: rating, elapsedTime: max(0, now.timeIntervalSince(shownAt)), desiredRetention: model.settings.desiredRetention, now: now)
            var next = session
            try next.record(updated, now: now)
            withAnimation(.easeIn(duration: 0.18)) { drag.width = (rating == .again ? -1 : 1) * max(width * 1.6, 600) }
            try? await Task.sleep(for: .milliseconds(190))
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                session = next; flipped = false; drag = .zero; shownAt = .now
                tint=nextTint
                nextTint=CardTint.allCases.filter{$0 != tint}.randomElement()!
            }
            try? await model.refresh()
            focused = true
        } catch {
            // Another window may edit/remove a word. Reload only this session's IDs.
            if let available = try? await db.practiceCards() { session.reconcile(available) }
            self.error = error.localizedDescription
            recenter()
        }
    }
}

private enum CardTint: CaseIterable {
    case yellow, green, blue, red
    var color: Color {
        switch self {
        case .yellow: Color(red: 0.98, green: 0.84, blue: 0.29)
        case .green: Color(red: 0.40, green: 0.77, blue: 0.57)
        case .blue: Color(red: 0.42, green: 0.67, blue: 0.94)
        case .red: Color(red: 0.94, green: 0.46, blue: 0.43)
        }
    }
}

private struct CardDictionarySelection:Identifiable {let id=UUID();let word:VocabularyDraft}
