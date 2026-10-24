import Foundation

public extension ReplacementSpan {
    /// Pronunciation always speaks the tapped target expression, never its sentence.
    var pronunciation: SentenceSpeechSegment { .init(text: targetSurface, languageCode: targetLanguageCode) }
}
import NaturalLanguage

public struct VocabularyContext: Sendable, Equatable {
    public let english: String
    public let mixed: String
}

public struct SentenceSpeechSegment: Sendable, Equatable {
    public let text: String
    public let languageCode: String
    public init(text: String, languageCode: String) { self.text = text; self.languageCode = languageCode }
}

extension GeneratedText {
    /// Saving a word retains its sentence, rather than silently archiving the whole reading.
    public func vocabularyContext(for span: ReplacementSpan) throws -> VocabularyContext {
        let sentenceRange = try contextRange(for: span)
        var mixed = "", cursor = sentenceRange.lowerBound
        for replacement in replacements.sorted(by: { $0.originalUTF16Range.location < $1.originalUTF16Range.location }) {
            let range = try replacement.originalUTF16Range.range(in: originalEnglish)
            guard range.lowerBound >= sentenceRange.lowerBound && range.upperBound <= sentenceRange.upperBound else { continue }
            mixed += originalEnglish[cursor..<range.lowerBound]
            mixed += replacement.targetSurface
            cursor = range.upperBound
        }
        mixed += originalEnglish[cursor..<sentenceRange.upperBound]
        return VocabularyContext(english: String(originalEnglish[sentenceRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            mixed: mixed.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func speechSegments(for span: ReplacementSpan, original: Bool = false) throws -> [SentenceSpeechSegment] {
        let sentence = try contextRange(for: span)
        if original { return [SentenceSpeechSegment(text: String(originalEnglish[sentence]), languageCode: "en")] }
        var segments: [SentenceSpeechSegment] = [], cursor = sentence.lowerBound
        func append(_ text: String, language: String) {
            guard !text.isEmpty else { return }
            if !text.contains(where: { $0.isLetter || $0.isNumber }), let last = segments.popLast() {
                segments.append(.init(text: last.text + text, languageCode: last.languageCode))
            } else { segments.append(.init(text: text, languageCode: language)) }
        }
        for replacement in replacements.sorted(by: { $0.originalUTF16Range.location < $1.originalUTF16Range.location }) {
            let range = try replacement.originalUTF16Range.range(in: originalEnglish)
            guard range.lowerBound >= sentence.lowerBound && range.upperBound <= sentence.upperBound else { continue }
            append(String(originalEnglish[cursor..<range.lowerBound]), language: "en")
            append(replacement.targetSurface, language: replacement.targetLanguageCode)
            cursor = range.upperBound
        }
        append(String(originalEnglish[cursor..<sentence.upperBound]), language: "en")
        return segments
    }

    private func contextRange(for span: ReplacementSpan) throws -> Range<String.Index> {
        _ = try renderedText()
        guard replacements.contains(where: { $0.id == span.id && $0 == span }) else { throw DomainError.missingRecord }
        let sourceRange = try span.originalUTF16Range.range(in: originalEnglish)
        if metadata["writingGenre"] == WritingGenre.poem.rawValue {
            let line = (originalEnglish as NSString).lineRange(for: NSRange(sourceRange, in: originalEnglish))
            guard let range = Range(line, in: originalEnglish) else { throw DomainError.invalidSpan }
            return range
        }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = originalEnglish
        tokenizer.setLanguage(.english)
        var sentenceRange = originalEnglish.startIndex..<originalEnglish.endIndex
        tokenizer.enumerateTokens(in: sentenceRange) { range, _ in
            if range.lowerBound <= sourceRange.lowerBound && range.upperBound >= sourceRange.upperBound {
                sentenceRange = range
                return false
            }
            return true
        }
        return sentenceRange
    }
}
