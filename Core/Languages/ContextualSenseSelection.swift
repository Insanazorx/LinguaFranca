import Foundation

public struct ContextualSenseOption: Sendable, Equatable {
    public let definition: String
    public let target: String
    public init(definition: String,target: String) { self.definition = definition; self.target = target }
}

public struct ContextualSenseRequest: Sendable, Equatable {
    public let expression: String
    public let partOfSpeech: String
    public let sentence: String
    public let languageCode: String
    public let options: [ContextualSenseOption]
    public init(expression: String,partOfSpeech: String,sentence: String,languageCode: String,options: [ContextualSenseOption]) {
        self.expression = expression; self.partOfSpeech = partOfSpeech; self.sentence = sentence; self.languageCode = languageCode; self.options = options
    }
    public func validate() throws {
        guard (1...9).contains(options.count), !expression.isEmpty, expression.count <= 80, sentence.count <= 1800,
              !sentence.contains("<|"), !expression.contains("<|"), options.allSatisfy({ !$0.target.isEmpty && $0.definition.count <= 240 && !$0.definition.contains("<|") && !$0.target.contains("<|") })
        else { throw DomainError.invalidInput("Invalid local dictionary sense selection.") }
    }
    public var prompt: String {
        // This is English sense classification, not multilingual translation. Target spelling
        // can bias a small model toward a familiar but unrelated dictionary entry.
        let choices = options.enumerated().map { "\($0.offset+1): \($0.element.definition.isEmpty ? "general dictionary sense" : $0.element.definition)" }.joined(separator:"\n")
        return "Which definition EXACTLY matches the marked \(partOfSpeech) '\(expression)'?\nSentence: \(sentence)\nClassify only the marked expression. A nearby word is not evidence for an unrelated meaning. A literal verb followed by a separate prepositional phrase is NOT an idiomatic phrasal verb. Return only a number.\n0: none of these meanings, literal non-idiomatic combination, or uncertain\n" + choices
    }
    public var grammar: String { "root ::= " + (0...options.count).map { "\"\($0)\"" }.joined(separator:" | ") + "\n" }
    public func selection(_ output: String) throws -> Int? {
        guard let number = Int(output.trimmingCharacters(in:.whitespacesAndNewlines)), (0...options.count).contains(number) else {
            throw GenerationError.invalidOutput("invalid dictionary option")
        }
        return number == 0 ? nil : number-1
    }
}

/// Optional semantic classification. The engine still chooses and renders only licensed lexical data.
public protocol ContextualSenseSelecting: Sendable {
    func selectSense(_ request: ContextualSenseRequest) async throws -> Int?
}
