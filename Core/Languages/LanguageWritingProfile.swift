import Foundation

/// Data-only capabilities shared by generation, validation and future language add-ons.
public struct LanguageWritingProfile: Codable, Sendable, Equatable {
    public enum Script: String, Codable, Sendable { case latin, cyrillic, arabic, hebrew, syriac }
    public let script: Script
    public let generationName: String
    public let systemLanguageDetection: Bool
    public init(script: Script, generationName: String, systemLanguageDetection: Bool = true) {
        self.script=script; self.generationName=generationName; self.systemLanguageDetection=systemLanguageDetection
    }
    public static func standard(_ code: String) -> Self {
        let script: Script
        switch code { case "ru": script = .cyrillic; case "ar": script = .arabic; case "he": script = .hebrew; case "syc": script = .syriac; default: script = .latin }
        let name=SemiticLanguage(rawValue:code)?.title ?? Locale(identifier:"en").localizedString(forLanguageCode:code) ?? code
        return .init(script:script,generationName:name,systemLanguageDetection:code != "la")
    }
    public var grammarLetters: String {
        switch script {
        case .latin: #"A-Za-z\u00C0-\u024F\u1E00-\u1EFF"#
        case .cyrillic: #"\u0400-\u052F"#
        case .arabic: #"\u0600-\u06FF"#
        case .hebrew: #"\u0590-\u05FF"#
        case .syriac: #"\u0700-\u074F"#
        }
    }
    public func accepts(_ text:String) -> Bool {
        let letters=text.precomposedStringWithCanonicalMapping.unicodeScalars.filter(CharacterSet.letters.contains)
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { scalar in
            switch script {
            case .latin: (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) || (0xC0...0x24F).contains(scalar.value) || (0x1E00...0x1EFF).contains(scalar.value)
            case .cyrillic: (0x400...0x52F).contains(scalar.value)
            case .arabic: (0x600...0x6FF).contains(scalar.value)
            case .hebrew: (0x590...0x5FF).contains(scalar.value)
            case .syriac: (0x700...0x74F).contains(scalar.value)
            }
        }
    }
}
