import SwiftUI
import AppKit

@MainActor final class MacApplicationDelegate:NSObject,NSApplicationDelegate {
    var prepareToTerminate:(@MainActor () async -> Void)?
    private var terminating=false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {true}
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else {return .terminateLater}
        guard let prepareToTerminate else {return .terminateNow}
        terminating=true
        Task {
            await prepareToTerminate()
            sender.reply(toApplicationShouldTerminate:true)
        }
        return .terminateLater
    }
}

enum MacSection:String,CaseIterable,Identifiable {
    case generate,study,vocabulary,dictionary,settings,readings
    var id:Self {self}
    var title:String {rawValue.capitalized}
    var number:Int {Self.allCases.firstIndex(of:self)!+1}
    var symbol:String {
        switch self {
        case .generate:"text.book.closed"
        case .study:"rectangle.on.rectangle"
        case .vocabulary:"character.book.closed"
        case .dictionary:"books.vertical"
        case .settings:"slider.horizontal.3"
        case .readings:"bookmark"
        }
    }
}

struct MacNavigationView:View {
    @Environment(AppEnvironment.self) private var model
    var body:some View {
        @Bindable var model=model
        NavigationSplitView {
            List(selection:$model.selectedSection) {
                Section {
                    ForEach([MacSection.generate,.readings,.study,.vocabulary,.dictionary,.settings]) {section in
                        Label(section.title,systemImage:section.symbol).tag(section)
                    }
                } header: {Label("LinguaFranca",systemImage:"leaf").font(.headline).padding(.vertical,12)}
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min:190,ideal:220,max:280)
        } detail: {
            switch model.selectedSection ?? .generate {
            case .generate:GenerateView()
            case .study:StudyView()
            case .vocabulary:VocabularyView()
            case .dictionary:DictionaryView()
            case .settings:SettingsView()
            case .readings:NavigationStack {SavedReadingsView()}
            }
        }
    }
}
