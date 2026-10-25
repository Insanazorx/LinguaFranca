import Foundation

public struct SyriacCorpusSlot: Sendable {
    public let range: UTF16Span
    public let form: SemiticWordForm
}
public struct SyriacCorpusTemplate: Sendable, Identifiable {
    public let id, text, reference, source, groupID: String
    public let slots: [SyriacCorpusSlot]
}

/// The first supported patterns are fixed, source-attested frames. Substituting
/// new inflections/lexemes is disabled until those grammar rules are reviewed.
public struct ClassicalSyriacTextRealizer: Sendable {
    private let lexicon: SemiticLexicon
    public init(lexicon: SemiticLexicon) { self.lexicon=lexicon }
    public func generate(request: VocabularyPracticeRequest, seed: UInt32) async throws -> AnnotatedVocabularyResult {
        try request.validate(); try Task.checkCancellation()
        guard request.languageCode == "syc" else { throw DomainError.invalidInput("This backend produces Classical Syriac only.") }
        let start = ContinuousClock.now
        let lexemes = Array(Set(request.expressions.flatMap { $0.lexicalForms.map(\.lexemeID) })).sorted()
        let templates = try await lexicon.corpusTemplates(lexemeIDs:lexemes)
        var rng = SeededGenerator(seed:UInt64(seed)), order = templates
        order.shuffle(using:&rng)
        var best: (SyriacCorpusTemplate,VocabularyCoverage)?
        for template in order {
            try Task.checkCancellation()
            guard SemiticUnicode.scriptMatches(template.text,language:"syc") else { continue }
            var annotations: [TargetVocabularyAnnotation] = []
            for slot in template.slots where slot.form.status == .attested {
                let surface = String(template.text[try slot.range.range(in:template.text)])
                guard SemiticUnicode.key(surface) == SemiticUnicode.key(slot.form.surface) else { throw DomainError.invalidSpan }
                let ids = request.expressions.filter { expression in
                    guard let ref=expression.lexicalReference else { return expression.lexicalForms.contains { $0.lexemeID==slot.form.lexemeID } }
                    switch ref.kind {
                    case .root: return ref.rootID != nil && ref.rootID==slot.form.rootID
                    case .lexeme: return ref.lexemeID==slot.form.lexemeID
                    case .wordForm:
                        return expression.lexicalForms.contains { $0.lexemeID==slot.form.lexemeID && SemiticUnicode.key($0.surface)==SemiticUnicode.key(slot.form.surface) && Set($0.tags).subtracting(["canonical"]).isSubset(of:Set(slot.form.tags)) }
                    }
                }.map(\.id)
                if !ids.isEmpty { annotations.append(.init(id:template.id+":"+String(slot.range.location),range:slot.range,surface:surface,vocabularyIDs:ids,forms:[slot.form])) }
            }
            let coverage = VocabularyPassageAnnotator.coverage(request:request,annotations:annotations,
                note:"Attested Classical Syriac corpus frame. Original word order and forms are preserved; no unrestricted topic or length is promised.",sources:[template.reference,template.source])
            if !coverage.usedIDs.isEmpty, coverage.usedIDs.count > (best?.1.usedIDs.count ?? 0) { best=(template,coverage) }
            if coverage.omittedIDs.isEmpty { break }
        }
        guard let (template,coverage)=best else { throw DomainError.invalidInput("No attested Syriac corpus pattern supports these selections. Choose another root or lexeme; no sentence was invented.") }
        let elapsed=start.duration(to:.now).components
        let result=GenerationResult(englishText:template.text,duration:Double(elapsed.seconds)+Double(elapsed.attoseconds)/1e18,
            modelIdentifier:"ETCBC-Classical-Syriac-0.9",seed:seed,tokenCount:0,metadata:["runtime":"deterministic-corpus-realizer","outputLanguage":"syc","contentSource":"attested-corpus-frame","templateID":template.id,"sourceReference":template.reference,"contextPolicy":"no-model-context"])
        return .init(generation:result,coverage:coverage)
    }
}
