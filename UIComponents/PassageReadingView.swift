import SwiftUI
import LinguaFrancaCore
import LinguaFrancaInference

struct PassageReadingView:View {
    @Environment(AppEnvironment.self) private var model
    let passage:GeneratedText
    @State private var mode="mixed"
    @State private var language="ru"
    @State private var saving=false
    @State private var error:String?
    private var ready:TargetReading? {model.narrationReadings[passage.id]?[language]}
    private var active:Bool {model.narrator.reading?.sourceTextID==passage.id}
    private var sentence:ReadingSentence? {
        guard model.narrator.followWords,active,let index=model.narrator.currentSentenceIndex,let ready,ready.sentences.indices.contains(index) else{return nil}
        return ready.sentences[index]
    }
    var body:some View {
        @Bindable var narrator=model.narrator
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:16) {
                Menu {
                    ForEach(model.narrationLanguages,id:\.self) {code in
                        Button(Theme.language(code)) {language=code;model.narrate(passage,languageCode:code)}
                    }
                } label: {Label("Listen",systemImage:"speaker.wave.2")}
                    .disabled(model.generating || model.remixing).accessibilityIdentifier("listen-reading")
                if active && narrator.state != .idle && narrator.state != .failed {
                    if narrator.state == .buffering {ProgressView().controlSize(.small)}
                    else {
                        Button(narrator.state == .paused ? "Resume":"Pause",systemImage:narrator.state == .paused ? "play.fill":"pause.fill") {
                            if narrator.state == .paused {narrator.resume()} else {narrator.pause()}
                        }.labelStyle(.iconOnly).accessibilityIdentifier("pause-reading")
                    }
                    Button("Stop",systemImage:"stop.fill"){narrator.stop()}.labelStyle(.iconOnly).accessibilityIdentifier("stop-reading")
                }
                Spacer()
                let saved=model.savedReadings.contains{$0.id==passage.id}
                Button(saved ? "Saved":"Save",systemImage:saved ? "bookmark.fill":"bookmark") {
                    saving=true
                    Task {do {try await model.saveReading(passage)} catch {self.error=error.localizedDescription};saving=false}
                }.disabled(saved || saving).accessibilityIdentifier("save-reading")
            }.buttonStyle(.bordered)
            if model.preparingNarrationID==passage.id {
                HStack {ProgressView().controlSize(.small);Text(model.generationPhase).font(.footnote);Spacer();Button("Cancel"){model.cancelGeneration()}}
            }
            if ready != nil {
                Picker("Text view",selection:$mode) {
                    Text("Mixed text").tag("mixed")
                    Text(Theme.language(language)).tag(language)
                }.pickerStyle(.segmented).accessibilityIdentifier("reading-view")
                Toggle("Follow spoken words",isOn:$narrator.followWords).font(.subheadline)
                    .onChange(of:narrator.followWords){_,enabled in if enabled {mode=language}}
                Text(Theme.language(language)+" · "+(model.narrationVoiceNames[language] ?? "")).font(.caption).foregroundStyle(.secondary)
            }
            if mode==language,let ready {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(ready.sentences) { part in
                        Text(russianText(part)).font(.system(.body,design:.serif)).lineSpacing(7)
                            .padding(.vertical,3)
                            .background(sentence?.id==part.id ? Theme.forest.opacity(0.08):.clear)
                    }
                }.accessibilityIdentifier("russian-reading-text")
            } else {
                InteractivePassageView(passage:passage,highlightedSourceRange:sentence?.sourceRange)
            }
            if active,let message=narrator.wordTrackingMessage {Text(message).font(.caption).foregroundStyle(.secondary)}
            if active,let message=narrator.errorMessage {Text(message).font(.footnote).foregroundStyle(.red)}
            if model.narrationErrorSourceID==passage.id,let message=model.narrationErrorMessage {Text(message).font(.footnote).foregroundStyle(.red)}
            if let error {Text(error).font(.footnote).foregroundStyle(.red)}
        }
        .onChange(of:ready?.sourceTextID) {_,id in if id != nil && narrator.followWords {mode=language}}
        .onAppear {if ready != nil && narrator.followWords {mode=language}}
        .onDisappear {
            if model.preparingNarrationID==passage.id {model.cancelGeneration()}
            else if active {narrator.stop()}
        }
    }
    private func russianText(_ part:ReadingSentence)->AttributedString {
        var text=AttributedString(part.translation)
        if sentence?.id==part.id,model.narrator.followWords,
           let span=model.narrator.currentWordRange,let range=try? span.range(in:part.translation),
           let lower=AttributedString.Index(range.lowerBound,within:text),let upper=AttributedString.Index(range.upperBound,within:text) {
            text[lower..<upper].backgroundColor = .yellow.opacity(0.75)
            text[lower..<upper].foregroundColor = .black
        }
        return text
    }
}
