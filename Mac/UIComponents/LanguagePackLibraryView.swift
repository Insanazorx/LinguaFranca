import SwiftUI
import UniformTypeIdentifiers
import LinguaFrancaCore

struct LanguagePackLibraryView:View {
    @Environment(AppEnvironment.self) private var model
    @State private var importing=false
    @State private var error:String?
    @State private var message:String?
    var body:some View {
        List {
            Section {
                Button("Add a language pack",systemImage:"plus.circle"){importing=true}
                    .disabled(model.generating || model.remixing || model.installingLanguagePack)
                    .accessibilityIdentifier("import-language-pack")
                Text("Choose a .lfpack folder from Files. Its dictionary becomes available for reading, search and study entirely offline.").font(.footnote).foregroundStyle(.secondary)
                if model.installingLanguagePack {ProgressView("Checking and adding language…")}
                if let message {Text(message).foregroundStyle(Theme.forest)}
                if let error {Text(error).foregroundStyle(.red)}
            }
            ForEach(model.languagePacks,id:\.id) {pack in
                Section(pack.displayName) {
                    LabeledContent("Version",value:pack.version)
                    Text(pack.licenseMetadata["attribution"] ?? pack.licenseMetadata["license"] ?? "")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Language packs")
            .fileImporter(isPresented:$importing,allowedContentTypes:[.folder,.package],allowsMultipleSelection:false) {selection in
                Task {
                    do {
                        guard let url=try selection.get().first else {return}
                        try await model.installLanguagePack(from:url);error=nil;message="Language added. You can enable it in Settings."
                    } catch {self.error=error.localizedDescription}
                }
            }
    }
}
