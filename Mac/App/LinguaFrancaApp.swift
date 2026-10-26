import SwiftUI
import AppKit
import LinguaFrancaCore
import CoreText

@main struct LinguaFrancaApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self) private var delegate
    @State private var environment = AppEnvironment()
    init() {
        if let font=Bundle.main.url(forResource:"NotoSansSyriac-Regular",withExtension:"ttf",subdirectory:"Fonts") {
            CTFontManagerRegisterFontsForURL(font as CFURL,.process,nil)
        }
    }
    var body: some Scene {
        WindowGroup("LinguaFranca") {
            appContent.frame(minWidth:960,minHeight:700)
                .onAppear {delegate.prepareToTerminate = {await environment.releaseModel()}}
        }
        .defaultSize(width:1140,height:820)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            CommandMenu("Navigate") {
                ForEach(MacSection.allCases) { section in
                    Button(section.title) {environment.selectedSection=section}
                        .keyboardShortcut(KeyEquivalent(Character(String(section.number))))
                }
            }
        }
        Settings { SettingsView().environment(environment).tint(Theme.forest).frame(width:680,height:740) }
    }
    private var appContent:some View {
        RootView().environment(environment).tint(Theme.forest)
            .task {await environment.open()}
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var model
    var body: some View {
        @Bindable var model = model
        Group {
            if model.loading {
                VStack(spacing: 20) {
                    Image(systemName: "text.book.closed.fill").font(.system(size: 48)).foregroundStyle(Theme.forest)
                    Text("LinguaFranca").font(.largeTitle.bold())
                    ProgressView("Opening your library…")
                }
            } else if model.database == nil {
                ContentUnavailableView {
                    Label("Library unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: { Text("Your saved data could not be opened.") } actions: {
                    Button("Try again") { Task { await model.open() } }
                }
            } else {
                if let session = model.reviewSession {
                    ReviewSessionView(cards: session.cards, onExit: { model.reviewSession = nil }).id(session.id)
                } else {
                    MacNavigationView()
                }
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

enum Theme {
    static let forest = Color(nsColor: NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.38,green:0.72,blue:0.55,alpha:1)
            : NSColor(srgbRed:0.17,green:0.35,blue:0.28,alpha:1)
    })
    static let paper = Color(nsColor:.windowBackgroundColor)
    static let german = Color(red: 0.55, green: 0.35, blue: 0.16)
    static let russian = Color(red: 0.38, green: 0.35, blue: 0.62)
    static func language(_ code: String) -> String { SemiticLanguage(rawValue:code)?.title ?? Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased() }
    static func accent(_ code: String) -> Color {
        switch code { case "de": german; case "ru": russian; case "ar": .teal; case "he": .blue; case "syc": .indigo; case "la": .brown; case "es": .orange; case "fr": .cyan; default: forest }
    }
}
