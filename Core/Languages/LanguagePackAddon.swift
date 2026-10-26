import Foundation
import CryptoKit
import GRDB

/// A .lfpack is a local folder containing only data, licenses and an offline search index.
/// The envelope binds every payload file to its size and SHA-256; it executes no code.
public struct LanguagePackAddon: Codable, Sendable {
    public struct File: Codable, Sendable {
        public let path:String
        public let byteCount:Int64
        public let sha256:String
    }
    public let formatVersion:Int
    public let metadataFile:String
    public let files:[File]

    public static func installedDirectories(in directory:URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath:directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles)
            .filter { $0.pathExtension == "lfpack" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    public static func validate(directory:URL) throws -> LanguagePackMetadata {
        try inspect(directory:directory).metadata
    }
    fileprivate static func inspect(directory:URL) throws -> (metadata:LanguagePackMetadata,envelope:Self) {
        let fm=FileManager.default
        func regular(_ relative:String) throws -> URL {
            guard !relative.hasPrefix("/"),!relative.split(separator:"/").contains(where: { $0 == ".." || $0 == "." }),
                  !relative.contains("\\"),!relative.isEmpty else { throw DomainError.invalidInput("Invalid language pack path.") }
            let path=directory.appendingPathComponent(relative)
            // Reject symlinks in both the file and its parents, including the selected folder.
            var cursor=path
            while cursor.path.count >= directory.path.count {
                guard try fm.attributesOfItem(atPath:cursor.path)[.type] as? FileAttributeType != .typeSymbolicLink else {
                    throw DomainError.invalidInput("Language packs cannot contain symbolic links.")
                }
                if cursor.standardizedFileURL == directory.standardizedFileURL { break }
                cursor.deleteLastPathComponent()
            }
            guard try fm.attributesOfItem(atPath:path.path)[.type] as? FileAttributeType == .typeRegular else {
                throw DomainError.invalidInput("A language pack file is missing.")
            }
            return path
        }
        let envelopeURL=try regular("addon.json")
        guard (try envelopeURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) < 64_000 else { throw DomainError.invalidInput("Invalid language pack manifest.") }
        let envelope=try JSONDecoder().decode(Self.self,from:Data(contentsOf:envelopeURL))
        guard envelope.formatVersion == 1,(3...10).contains(envelope.files.count),
              envelope.metadataFile.hasPrefix("en-"),envelope.metadataFile.hasSuffix(".json"),!envelope.metadataFile.contains("/"),
              Set(envelope.files.map(\.path)).count == envelope.files.count,
              envelope.files.allSatisfy({ (1...536_870_912).contains($0.byteCount) && $0.sha256.count == 64 && $0.sha256.allSatisfy(\.isHexDigit) }),
              envelope.files.reduce(Int64(0),{ $0+$1.byteCount }) <= 805_306_368 else {
            throw DomainError.invalidInput("Unsupported or oversized language pack.")
        }
        for file in envelope.files {
            try Task.checkCancellation()
            let url=try regular(file.path)
            guard try url.resourceValues(forKeys:[.fileSizeKey]).fileSize == Int(file.byteCount) else { throw DomainError.invalidInput("Language pack file size mismatch.") }
            let handle=try FileHandle(forReadingFrom:url);defer { try? handle.close() }
            var hash=SHA256()
            while let bytes=try autoreleasepool(invoking:{try handle.read(upToCount:1024*1024)}),!bytes.isEmpty { hash.update(data:bytes);try Task.checkCancellation() }
            guard hash.finalize().map({String(format:"%02x",$0)}).joined() == file.sha256.lowercased() else { throw DomainError.invalidInput("Language pack checksum mismatch.") }
        }
        let metadata=try JSONDecoder().decode(LanguagePackMetadata.self,from:Data(contentsOf:try regular(envelope.metadataFile)))
        let code=metadata.languageCode
        guard (2...3).contains(code.count),code.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }),
              metadata.id == "en-"+code,metadata.schemaVersion == 1,metadata.lexiconDatabaseName == "en-"+code+".sqlite",
              envelope.metadataFile == metadata.id+".json",!metadata.version.isEmpty,!metadata.displayName.isEmpty,
              !metadata.licenseMetadata.isEmpty,let profile=metadata.writingProfile,
              (1...80).contains(profile.generationName.count),profile.generationName.allSatisfy({$0.isLetter || " '-()".contains($0)}) else { throw DomainError.invalidInput("Invalid language pack metadata.") }
        let required:Set<String>=[envelope.metadataFile,metadata.lexiconDatabaseName,"_dictionary/search.sqlite","LICENSE.txt"]
        let allowed=required.union([metadata.id+".policy.json","_dictionary/manifest.json"])
        guard required.isSubset(of:Set(envelope.files.map(\.path))),Set(envelope.files.map(\.path)).isSubset(of:allowed) else { throw DomainError.invalidInput("Incomplete language pack.") }
        var config=Configuration();config.readonly=true
        let lexicon=try DatabaseQueue(path:try regular(metadata.lexiconDatabaseName).path,configuration:config)
        try lexicon.read { db in
            guard try String.fetchOne(db,sql:"PRAGMA quick_check") == "ok",
                  try Int.fetchOne(db,sql:"SELECT count(*) FROM entry") ?? 0 > 0 else { throw DomainError.invalidInput("Invalid lexical database.") }
            _ = try Row.fetchAll(db,sql:"SELECT lemma,pos,senseID,definition,translations,score,provenance FROM entry LIMIT 1")
        }
        let search=try DatabaseQueue(path:try regular("_dictionary/search.sqlite").path,configuration:config)
        try search.read { db in
            guard try String.fetchOne(db,sql:"PRAGMA quick_check") == "ok",
                  try Int.fetchOne(db,sql:"SELECT count(*) FROM pack") == 1,
                  try String.fetchOne(db,sql:"SELECT language FROM pack") == code,
                  try Int.fetchOne(db,sql:"SELECT count(*) FROM document WHERE language != ?",arguments:[code]) == 0,
                  let json=try String.fetchOne(db,sql:"SELECT metadata FROM pack"),
                  try JSONDecoder().decode(LanguagePackMetadata.self,from:Data(json.utf8)) == metadata else { throw DomainError.invalidInput("Language pack search index does not match its dictionary.") }
            _ = try Row.fetchAll(db,sql:"SELECT rowid FROM search WHERE search MATCH ? LIMIT 1",arguments:["test"])
        }
        return (metadata,envelope)
    }
}

public actor LanguagePackInstaller {
    public let directory:URL
    public init(directory:URL) { self.directory=directory }
    public func install(from selected:URL,existingCodes:Set<String>) throws -> LanguagePackMetadata {
        let fm=FileManager.default
        let inspected=try LanguagePackAddon.inspect(directory:selected),metadata=inspected.metadata
        guard !existingCodes.contains(metadata.languageCode) else { throw DomainError.invalidInput("This language is already installed.") }
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        let staging=directory.appendingPathComponent(".incoming-"+UUID().uuidString,isDirectory:true)
        defer { try? fm.removeItem(at:staging) }
        let envelope=inspected.envelope
        try fm.createDirectory(at:staging,withIntermediateDirectories:true)
        for file in envelope.files {
            let target=staging.appendingPathComponent(file.path)
            try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try fm.copyItem(at:selected.appendingPathComponent(file.path),to:target)
        }
        try JSONEncoder().encode(envelope).write(to:staging.appendingPathComponent("addon.json"),options:.atomic)
        // Validate the private snapshot, so changing an external file during copying cannot publish a damaged pack.
        _ = try LanguagePackAddon.validate(directory:staging)
        try Task.checkCancellation()
        try fm.moveItem(at:staging,to:directory.appendingPathComponent(metadata.id+".lfpack",isDirectory:true))
        return metadata
    }
}
