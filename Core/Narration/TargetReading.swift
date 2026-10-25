import Foundation
import NaturalLanguage

public struct ReadingSentence: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let sourceRange: UTF16Span
    public let source: String
    public let translation: String
    public init(id:Int,sourceRange:UTF16Span,source:String,translation:String) {
        self.id=id;self.sourceRange=sourceRange;self.source=source;self.translation=translation
    }
}

public struct TargetReading: Codable, Sendable, Equatable {
    public let sourceTextID: String
    public let languageCode: String
    public let sentences: [ReadingSentence]
    public var text:String {sentences.map(\.translation).joined(separator:"\n\n")}
    public init(sourceTextID:String,languageCode:String,sentences:[ReadingSentence]) {
        self.sourceTextID=sourceTextID;self.languageCode=languageCode;self.sentences=sentences
    }
    public func validate(for passage:GeneratedText) throws {
        guard sourceTextID==passage.id,!sentences.isEmpty,!languageCode.isEmpty else {throw DomainError.invalidInput("The reading does not match its source.")}
        var cursor=passage.originalEnglish.startIndex
        for (index,sentence) in sentences.enumerated() {
            let range=try sentence.sourceRange.range(in:passage.originalEnglish)
            guard sentence.id==index,range.lowerBound>=cursor,
                  passage.originalEnglish[cursor..<range.lowerBound].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  String(passage.originalEnglish[range])==sentence.source,!sentence.translation.isEmpty else {throw DomainError.invalidSpan}
            cursor=range.upperBound
        }
        guard passage.originalEnglish[cursor...].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw DomainError.invalidSpan}
    }
}

public struct ReadingTranslationTask: Sendable, Equatable {
    public let source, previous, following, languageCode:String
    public init(source:String,previous:String="",following:String="",languageCode:String="ru") {
        self.source=source;self.previous=previous;self.following=following;self.languageCode=languageCode
    }
    public func validate() throws {
        guard languageCode=="ru",(1...1400).contains(source.count),previous.count<=350,following.count<=350,
              ![source,previous,following].contains(where:{$0.contains("<|") || $0.contains("\0")}) else {
            throw DomainError.invalidInput("Invalid reading translation request.")
        }
    }
    public var prompt:String {
        """
        Переведи с английского на естественный русский. Переведи все слова, в том числе устойчивые выражения; не оставляй английских фраз. Передай имена кириллицей. Сохрани смысл, все детали и числа. Не добавляй новые события. Верни только JSON {"translation":"русский перевод"}.
        Текст для перевода:
        \(source)
        """
    }
    public var grammar:String {
        #"""
        root ::= "{" ws "\"translation\":" ws string ws "}"
        ws ::= [ \t\n\r]*
        string ::= "\"" ([А-Яа-яЁё0-9 .,!?;:()'/%+№€$£—–…«»„“”\x2D] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\""
        """#
    }
    public func translation(from output:String) throws -> String {
        struct Response:Decodable {let translation:String}
        let response:Response
        do {response=try JSONDecoder().decode(Response.self,from:Data(output.utf8))}
        catch {throw GenerationError.invalidOutput("The reading translation was incomplete. Please try again.")}
        let text=response.translation.trimmingCharacters(in:.whitespacesAndNewlines)
        let letters=text.unicodeScalars.filter{CharacterSet.letters.contains($0)}
        let cyrillic=letters.filter{(0x0400...0x052F).contains($0.value)}.count
        guard !text.contains("<|"),!text.contains("```"),(1...1400).contains(text.count),
              !letters.isEmpty,cyrillic==letters.count else {
            throw GenerationError.invalidOutput("Russian translation did not contain valid Russian text")
        }
        func numbers(_ value:String)->[String] {
            let expression=try! NSRegularExpression(pattern:"[0-9]+")
            return expression.matches(in:value,range:NSRange(value.startIndex...,in:value)).map{(value as NSString).substring(with:$0.range)}.sorted()
        }
        let expected=numbers(source),actual=numbers(text)
        if expected != actual {
            let formatter=NumberFormatter();formatter.locale=Locale(identifier:"ru_RU");formatter.numberStyle = .spellOut
            let writtenOut=actual.isEmpty && !expected.isEmpty && expected.allSatisfy { number in
                guard let value=Int(number),value>=0,value<=1_000_000,
                      let spelling=formatter.string(from:NSNumber(value:value)) else{return false}
                return text.lowercased().contains(spelling.lowercased())
            }
            guard writtenOut else {throw GenerationError.invalidOutput("The translation changed a number")}
        }
        return text
    }
}

public actor TargetReadingTranslator {
    private let model:any TextGenerationService
    public init(model:any TextGenerationService) {self.model=model}
    public func translate(_ passage:GeneratedText,languageCode:String="ru",progress:@Sendable (Int,Int) async -> Void = {_,_ in}) async throws -> TargetReading {
        guard languageCode=="ru" else {throw DomainError.invalidInput("A reading voice for this language is not installed.")}
        let chunks=try Self.sourceSentences(passage.originalEnglish)
        var translated:[ReadingSentence]=[]
        for (index,chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            await progress(index,chunks.count)
            let task=ReadingTranslationTask(source:chunk.source,
                previous:index>0 ? String(chunks[index-1].source.suffix(350)):"",
                following:index+1<chunks.count ? String(chunks[index+1].source.prefix(350)):"",languageCode:languageCode)
            var config=GenerationConfiguration();config.temperature=0.2;config.maximumTokens=768;config.repetitionPenalty=1.05
            var request=GenerationRequest(topic:"Faithful reading translation",seed:passage.seed &+ UInt32(index),configuration:config)
            request.readingTranslation=task
            let result=try await model.generate(request:request)
            let text=try task.translation(from:result.englishText)
            translated.append(.init(id:index,sourceRange:chunk.sourceRange,source:chunk.source,translation:text))
        }
        await progress(chunks.count,chunks.count)
        return TargetReading(sourceTextID:passage.id,languageCode:languageCode,sentences:translated)
    }
    public static func sourceSentences(_ text:String) throws -> [ReadingSentence] {
        guard !text.isEmpty,text.count<=20000 else {throw DomainError.invalidInput("Invalid reading length.")}
        let tokenizer=NLTokenizer(unit:.sentence);tokenizer.string=text;tokenizer.setLanguage(.english)
        var chunks:[ReadingSentence]=[]
        tokenizer.enumerateTokens(in:text.startIndex..<text.endIndex) {range,_ in
            let trimmed=String(text[range]).trimmingCharacters(in:.whitespacesAndNewlines)
            if !trimmed.isEmpty,let exact=text.range(of:trimmed,range:range) {
                let ns=NSRange(exact,in:text)
                chunks.append(.init(id:chunks.count,sourceRange:.init(location:ns.location,length:ns.length),source:trimmed,translation:""))
            }
            return true
        }
        guard !chunks.isEmpty,chunks.count<=100,chunks.allSatisfy({$0.source.count<=1400}) else {throw DomainError.invalidInput("A sentence is too long for the local reading model.")}
        return chunks
    }
}

extension GeneratedText {
    /// Maps an intact source sentence to the reversible mixed text's offsets.
    public func renderedSpan(for source:UTF16Span) throws -> UTF16Span {
        _=try source.range(in:originalEnglish)
        let start=source.location,end=start+source.length
        var before=0,inside=0
        for replacement in replacements {
            let lower=replacement.originalUTF16Range.location,upper=lower+replacement.originalUTF16Range.length
            let delta=replacement.targetSurface.utf16.count-replacement.originalUTF16Range.length
            if upper<=start {before+=delta}
            else if lower>=start && upper<=end {inside+=delta}
            else if lower<end && upper>start {throw DomainError.invalidSpan}
        }
        return UTF16Span(location:start+before,length:source.length+inside)
    }
}
