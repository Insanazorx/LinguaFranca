import SwiftUI
import UIKit
import LinguaFrancaCore
import CoreText

@main struct LinguaFrancaApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var phase
    init() {
        if let font=Bundle.main.url(forResource:"NotoSansSyriac-Regular",withExtension:"ttf",subdirectory:"Fonts") {
            CTFontManagerRegisterFontsForURL(font as CFURL,.process,nil)
        }
    }
    var body: some Scene {
        WindowGroup {
            appContent
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await environment.handleMemoryPressure() }
                }
        }
    }
    private var appContent:some View {
        RootView().environment(environment).tint(Theme.forest)
            .task {await environment.open()}
            .onChange(of:keepsDisplayAwake,initial:true) {_,active in
                UIApplication.shared.isIdleTimerDisabled = active && phase == .active
            }
            .onChange(of:phase) {_,value in
                UIApplication.shared.isIdleTimerDisabled = value == .active && keepsDisplayAwake
                if value == .background {Task {await environment.releaseModel()}}
            }
    }
    private var keepsDisplayAwake:Bool {
        environment.generating || environment.remixing || environment.narrator.state == .playing || environment.narrator.state == .buffering
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
                TabView {
                    GenerateView().tabItem { Label("Generate", systemImage: "text.book.closed") }
                    StudyView().tabItem { Label("Study", systemImage: "rectangle.on.rectangle") }
                    VocabularyView().tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
                    DictionaryView().tabItem { Label("Dictionary", systemImage: "books.vertical") }
                    SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

enum Theme {
    static let forest = Color(red: 0.17, green: 0.35, blue: 0.28)
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let german = Color(red: 0.55, green: 0.35, blue: 0.16)
    static let russian = Color(red: 0.38, green: 0.35, blue: 0.62)
    static func language(_ code: String) -> String { SemiticLanguage(rawValue:code)?.title ?? Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased() }
    static func accent(_ code: String) -> Color {
        switch code { case "de": german; case "ru": russian; case "ar": .teal; case "he": .blue; case "syc": .indigo; default: forest }
    }
}
