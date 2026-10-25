import Foundation

public struct TargetVocabularyAnnotation: Sendable, Identifiable {
    public let id: String
    public let range: UTF16Span
    public let surface: String
    public let vocabularyIDs: [String]
    public let forms: [SemiticWordForm]
}

public struct VocabularyCoverage: Sendable {
    public let selectedIDs, usedIDs, omittedIDs: [String]
    public let annotations: [TargetVocabularyAnnotation]
    public let validationNote: String
    public let sourceReferences: [String]
}

public enum VocabularyPassageAnnotator {
    public static func analyze(_ text: String, request: VocabularyPracticeRequest, lexicon: SemiticLexicon) async throws -> VocabularyCoverage {
        guard SemiticLanguage(rawValue:request.languageCode) != nil else { return try analyze(text,request:request) }
        let regex=try NSRegularExpression(pattern:#"\p{L}[\p{L}\p{M}]*"#)
        var annotations: [TargetVocabularyAnnotation] = []
        var cache: [String:[SemiticWordForm]] = [:]
        for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)) {
            try Task.checkCancellation()
            let surface=(text as NSString).substring(with:match.range), key=SemiticUnicode.key(surface)
            let forms: [SemiticWordForm]
            if let existing=cache[key] { forms=existing }
            else { forms=try await lexicon.forms(matching:surface,language:request.languageCode);cache[key]=forms }
            var ids: [String] = [], accepted: [SemiticWordForm] = []
            for expression in request.expressions {
                let matches=forms.filter { form in
                    guard let ref=expression.lexicalReference else { return expression.lexicalForms.contains { $0.lexemeID==form.lexemeID } }
                    switch ref.kind {
                    case .root: return ref.rootID != nil && ref.rootID==form.rootID
                    case .lexeme: return ref.lexemeID==form.lexemeID
                    case .wordForm: return expression.lexicalForms.contains { $0.lexemeID==form.lexemeID && SemiticUnicode.key($0.surface)==key && Set($0.tags).subtracting(["canonical"]).isSubset(of:Set(form.tags)) }
                    }
                }
                if !matches.isEmpty { ids.append(expression.id);accepted+=matches }
            }
            if !ids.isEmpty {
                var seen: Set<String> = []
                annotations.append(.init(id:String(match.range.location),range:.init(location:match.range.location,length:match.range.length),surface:surface,vocabularyIDs:ids,forms:accepted.filter{seen.insert($0.id).inserted}))
            }
        }
        return coverage(request:request,annotations:annotations,note:"Lexical forms and selected families checked against the offline pack. Possible analyses are shown; full sentence grammar is not certified.",sources:[])
    }
    public static func analyze(_ text: String, request: VocabularyPracticeRequest) throws -> VocabularyCoverage {
        guard SemiticLanguage(rawValue:request.languageCode) != nil else {
            return .init(selectedIDs:request.expressions.map(\.id),usedIDs:request.expressions.map(\.id),omittedIDs:[],annotations:[],validationNote:"Selected dictionary expressions checked.",sourceReferences:[])
        }
        let regex = try NSRegularExpression(pattern:#"\p{L}[\p{L}\p{M}]*"#)
        var annotations: [TargetVocabularyAnnotation] = []
        for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)) {
            let surface = (text as NSString).substring(with:match.range), normalized = SemiticUnicode.key(surface)
            var ids: [String] = [], forms: [SemiticWordForm] = []
            for expression in request.expressions {
                let verified = expression.lexicalForms.filter { $0.status == .attested && SemiticUnicode.key($0.surface) == normalized }
                if !verified.isEmpty { ids.append(expression.id); forms += verified }
            }
            if !ids.isEmpty {
                var seen: Set<String> = []
                annotations.append(.init(id:String(match.range.location),range:.init(location:match.range.location,length:match.range.length),surface:surface,
                    vocabularyIDs:ids.sorted(),forms:forms.filter { seen.insert($0.id).inserted }))
            }
        }
        return coverage(request:request,annotations:annotations,note:"Dictionary forms verified. Ambiguous analyses are retained; complete sentence grammar is not certified.",sources:[])
    }
    static func coverage(request: VocabularyPracticeRequest, annotations: [TargetVocabularyAnnotation], note: String, sources:[String]) -> VocabularyCoverage {
        let used = Set(annotations.flatMap(\.vocabularyIDs)), selected = request.expressions.map(\.id)
        return .init(selectedIDs:selected,usedIDs:selected.filter { used.contains($0) },omittedIDs:selected.filter { !used.contains($0) },annotations:annotations,validationNote:note,sourceReferences:sources)
    }
}

public struct AnnotatedVocabularyResult: Sendable {
    public let generation: GenerationResult
    public let coverage: VocabularyCoverage
}

/// One selected-vocabulary workflow; only the backend changes for Classical Syriac.
public struct VocabularyTextGenerator: Sendable {
    private let model: any TextGenerationService
    private let lexicon: SemiticLexicon
    public init(model: any TextGenerationService, lexicon: SemiticLexicon) { self.model=model; self.lexicon=lexicon }
    public func generate(request: GenerationRequest) async throws -> AnnotatedVocabularyResult {
        guard let practice=request.vocabularyPractice else { throw DomainError.invalidInput("Select vocabulary first.") }
        if practice.languageCode == "syc" {
            return try await ClassicalSyriacTextRealizer(lexicon:lexicon).generate(request:practice,seed:request.seed)
        }
        let attempts=SemiticLanguage(rawValue:practice.languageCode) == nil ? 1 : 2
        var best: AnnotatedVocabularyResult?
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            var next=request;next.seed=request.seed &+ UInt32(attempt)
            do {
                let result=try await model.generate(request:next)
                let coverage=try await VocabularyPassageAnnotator.analyze(result.englishText,request:practice,lexicon:lexicon)
                if best == nil || coverage.usedIDs.count > best!.coverage.usedIDs.count { best = .init(generation:result,coverage:coverage) }
                if coverage.omittedIDs.isEmpty { break }
            } catch is CancellationError { throw CancellationError() }
            catch { if attempt==attempts-1 && best == nil { throw error } }
        }
        guard let best else { throw GenerationError.invalidOutput("no valid vocabulary passage") }
        return best
    }
}
