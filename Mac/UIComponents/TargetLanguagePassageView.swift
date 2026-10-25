import SwiftUI
import LinguaFrancaCore

struct SemiticOrLatinVocabularyText: View {
    let text,language: String
    var size:CGFloat?=nil
    var body: some View {
        if SemiticUnicode.isRightToLeft(language) { SemiticNativeText(text:text,language:language,size:size ?? 24) }
        else { Text(text).font(size.map { .system(size:$0,design:.serif) } ?? .title3) }
    }
}

struct TargetLanguagePassageView: View {
    let reading: VocabularyPracticeReading
    @State private var selected: TargetVocabularyAnnotation?
    var body: some View {
        Text(attributed).font(reading.languageCode == "syc" ? .custom("NotoSansSyriac-Regular",size:22,relativeTo:.body) : .system(.body,design:.serif))
            .lineSpacing(6)
            .environment(\.layoutDirection,SemiticUnicode.isRightToLeft(reading.languageCode) ? .rightToLeft : .leftToRight)
            .environment(\.openURL,OpenURLAction { url in
                guard url.scheme=="linguafranca",url.host=="morphology",let id=Int(url.lastPathComponent),
                      let annotations=reading.coverage?.annotations,annotations.indices.contains(id) else { return .systemAction }
                selected=annotations[id];return .handled
            })
            .sheet(item:$selected) { annotation in
                TargetMorphologySheet(annotation:annotation,language:reading.languageCode).nativeSheetSize()
            }
    }
    private var attributed: AttributedString {
        guard let annotations=reading.coverage?.annotations,!annotations.isEmpty else { return AttributedString(reading.text) }
        do {
            var result=AttributedString(),cursor=reading.text.startIndex
            for (index,annotation) in annotations.enumerated().sorted(by:{$0.element.range.location<$1.element.range.location}) {
                let range=try annotation.range.range(in:reading.text)
                guard range.lowerBound>=cursor else { continue }
                result+=AttributedString(String(reading.text[cursor..<range.lowerBound]))
                var word=AttributedString(String(reading.text[range]))
                word.link=URL(string:"linguafranca://morphology/"+String(index))
                word.foregroundColor=Theme.accent(reading.languageCode);word.underlineStyle = .single
                result+=word;cursor=range.upperBound
            }
            result+=AttributedString(String(reading.text[cursor...]));return result
        } catch { return AttributedString(reading.text) }
    }
}

struct TargetMorphologySheet: View {
    @Environment(AppEnvironment.self) private var model
    let annotation: TargetVocabularyAnnotation
    let language: String
    @State private var selection = 0
    @State private var lexeme: SemiticLexeme?
    @State private var root: SemiticRoot?
    @State private var save: VocabularyDraft?
    @State private var speech = SentenceSpeechController()
    private var form: SemiticWordForm? { annotation.forms.indices.contains(selection) ? annotation.forms[selection] : nil }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SemiticNativeText(text:annotation.surface,language:language,size:34)
                    if annotation.forms.count>1 {
                        Text("This spelling has several recorded analyses. Context may narrow them further.").font(.footnote).foregroundStyle(.secondary)
                        Picker("Analysis",selection:$selection) {
                            ForEach(annotation.forms.indices,id:\.self) { i in Text(annotation.forms[i].analysis.isEmpty ? "Dictionary form" : annotation.forms[i].analysis).tag(i) }
                        }
                    }
                    if let form {
                        Text(form.transliteration);Text(form.analysis)
                        Link("Form source",destination:URL(string:form.source)!)
                    }
                    if let lexeme {
                        Text(lexeme.gloss);Text(lexeme.pattern).foregroundStyle(.secondary)
                        Button("Save lexeme to list") { save=lexeme.vocabularyDraft }
                        if let form { Button("Save this form") { save=form.vocabularyDraft(for:lexeme) } }
                    }
                    if let root { NavigationLink("Root family") { SemiticRootDetailView(root:root) } }
                    if SentenceSpeechController.hasLocalVoice(language) {
                        Button(speech.isSpeaking ? "Stop pronunciation" : "Pronounce") {
                            if speech.isSpeaking { speech.stop() } else { speech.speak([.init(text:annotation.surface,languageCode:language)]) }
                        }
                    }
                }
            }.nativeFormStyle().navigationTitle("Word & morphology").inlineNavigationTitle()
            .task(id:selection) {
                guard let form,let catalog=model.semiticLexicon else{return}
                do {
                    lexeme=try await catalog.lexeme(id:form.lexemeID,language:language)
                    root=nil
                    if let id=form.rootID { root=try await catalog.root(id:id,language:language) }
                } catch { model.errorMessage=error.localizedDescription }
            }
            .sheet(isPresented:Binding(get:{save != nil},set:{if !$0 {save=nil}})) { if let save { SemiticSaveSheet(draft:save) } }
        }.onDisappear { speech.stop() }
    }
}
