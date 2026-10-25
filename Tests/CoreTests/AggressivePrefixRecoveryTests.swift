import Testing
import Foundation
@testable import LinguaFrancaCore

@Test func truncatedBilingualDraftKeepsOnlyCompleteDecodedMappings() throws {
    let output=#"{"english":"The moon shines above the garden.","replacements":[{"source":"moon","target":"луна","language":"ru","occurrence":0},{"source":"garden","target":"сад""#
    let draft=try AggressiveDraft.decodeRetainingSource(output)
    #expect(draft.english=="The moon shines above the garden.")
    #expect(draft.replacements.count==1)
    #expect(draft.replacements[0].source=="moon" && draft.replacements[0].target=="луна")
    #expect(draft.replacements[0].language=="ru" && draft.replacements[0].occurrence==0)
}

@Test func prefixRecoveryRespectsQuotedBracesBackslashesAndUnicode() throws {
    let output=#"{"english":"A \"moon\" 🙂 and a garden.","replacements":[{"source":"\"moon\"","target":"луна {свет}","language":"ru","occurrence":0},{"source":"garden","target":"сад","language":"ru","occurrence":0},"#
    let draft=try AggressiveDraft.decodeRetainingSource(output)
    #expect(draft.english=="A \"moon\" 🙂 and a garden.")
    #expect(draft.replacements.map(\.target)==["луна {свет}","сад"])
    #expect(draft.replacements[0].source=="\"moon\"")
}

@Test func invalidOrMissingMappingFieldsNeverBecomeRecoveredTranslations() throws {
    let output=#"{"english":"A garden.","replacements":[{"source":"garden","target":"сад","language":"ru"},{"source":"garden","target":"сад","language":"ru","occurrence":0},"#
    #expect(try AggressiveDraft.decodeRetainingSource(output).replacements.isEmpty)
    #expect(try AggressiveDraft.decodeRetainingSource(#"{"english":"A garden.","wrongKey":[{"source":"garden","target":"сад","language":"ru","occurrence":0}"#).replacements.isEmpty)
    #expect(throws:GenerationError.self) {try AggressiveDraft.decodeRetainingSource(#"{"english":"A gar"#)}
}

@Test func everyTruncationBoundaryRetainsOnlyAnExactPrefixOfMappings() throws {
    let full=AggressiveDraft(english:"A \"garden\" 🙂 and a moon.",replacements:[
        .init(source:"garden",target:"сад {зелёный}",language:"ru",occurrence:0),
        .init(source:"moon",target:"луна \\",language:"ru",occurrence:0)
    ])
    let encoded=String(decoding:try JSONEncoder().encode(full),as:UTF8.self)
    // Use the actual native grammar's fixed field order rather than JSONEncoder's key order.
    let english=String(decoding:try JSONEncoder().encode(full.english),as:UTF8.self)
    let mappings=String(decoding:try JSONEncoder().encode(full.replacements),as:UTF8.self)
    let json="{\"english\":"+english+",\"replacements\":"+mappings+"}"
    #expect(try AggressiveDraft.decode(encoded).replacements.count==2)
    for boundary in json.indices {
        guard let recovered=try? AggressiveDraft.decodeRetainingSource(String(json[..<boundary])) else {continue}
        #expect(recovered.english==full.english)
        #expect(recovered.replacements.count<=full.replacements.count)
        for (actual,expected) in zip(recovered.replacements,full.replacements) {
            #expect(actual.source==expected.source && actual.target==expected.target)
            #expect(actual.language==expected.language && actual.occurrence==expected.occurrence)
        }
    }
}
