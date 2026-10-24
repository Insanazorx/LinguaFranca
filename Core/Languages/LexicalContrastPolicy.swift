import Foundation

/// Filters transparent translation pairs; this is not an etymology classifier.
public enum LexicalContrastPolicy {
    public static func isDistinct(english: String, target: String) -> Bool {
        guard english.count <= 100, target.count <= 100 else { return false }
        let source = key(english), translated = key(target)
        guard !source.isEmpty, !translated.isEmpty, source != translated else { return false }
        // Short unrelated words often differ by one letter (and/und, he/er).
        guard min(source.count, translated.count) >= 4 else { return true }
        if similarity(source, translated) >= 0.75 { return false }
        let a = stem(source), b = stem(translated)
        return min(a.count, b.count) < 4 || similarity(a, b) < 0.8
    }

    private static func key(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        var value = latin.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isASCII && $0.isLetter }
        for suffix in ["tsiya", "tsia", "cija", "ciia", "cia"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count)) + "tion"
            break
        }
        for (from, to) in [("ph", "f"), ("ch", "s"), ("sh", "s"), ("ck", "k"), ("qu", "kv"),
                           ("ce", "se"), ("ci", "si"), ("cy", "si"), ("c", "k"), ("w", "v"), ("y", "i")] {
            value = value.replacingOccurrences(of: from, with: to)
        }
        return value
    }

    private static func stem(_ value: String) -> String {
        // International noun endings; remove at most one and retain a meaningful stem.
        for suffix in ["ation", "ition", "akija", "ikija", "akion", "ierung", "ismus", "nost", "akia", "ikia", "itat", "itet", "ity", "iti", "ija", "ion", "ia", "ie", "ik", "ic", "a", "e", "i", "s"] {
            if value.hasSuffix(suffix), value.count - suffix.count >= 4 { return String(value.dropLast(suffix.count)) }
        }
        return value
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        let left = Array(a), right = Array(b)
        var previous = Array(0...right.count)
        for (i, first) in left.enumerated() {
            var row = [i + 1]
            for (j, second) in right.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (first == second ? 0 : 1)))
            }
            previous = row
        }
        return 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
    }
}
