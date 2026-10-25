import SwiftUI
import LinguaFrancaCore

struct SavedReadingsView:View {
    @Environment(AppEnvironment.self) private var model
    @State private var query=""
    @State private var deleted:SavedReadingSummary?
    @State private var renamed:SavedReadingSummary?
    @State private var title=""
    private var visible:[SavedReadingSummary] {model.savedReadings.filter{query.isEmpty || ($0.title+" "+$0.preview).localizedCaseInsensitiveContains(query)}}
    var body:some View {
        List {
            if model.savedReadings.isEmpty {
                ContentUnavailableView("Save a good read",systemImage:"books.vertical",description:Text("Tap Save above a generated text. Your saved texts stay here for reading and listening."))
            }
            ForEach(visible) { reading in
                NavigationLink {SavedReadingDetailView(id:reading.id)} label: {
                    VStack(alignment:.leading,spacing:6) {
                        Text(reading.title).font(.headline)
                        Text(reading.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        Text(reading.savedAt,format:.dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,6)
                }
                .contextMenu {
                    Button("Rename"){title=reading.title;renamed=reading}
                    Button("Delete",role:.destructive){deleted=reading}
                }
                .swipeActions {Button("Delete",role:.destructive){deleted=reading}}
            }
        }.navigationTitle("Saved readings").searchable(text:$query,prompt:"Title or text preview")
            .task {try? await model.refresh()}
            .alert("Delete saved text?",isPresented:Binding(get:{deleted != nil},set:{if !$0 {deleted=nil}})) {
                Button("Delete",role:.destructive){if let deleted {Task {await model.deleteSavedReading(deleted.id)}};deleted=nil}
                Button("Cancel",role:.cancel){deleted=nil}
            } message: {Text("Your saved vocabulary and study history stay in your lists.")}
            .alert("Rename text",isPresented:Binding(get:{renamed != nil},set:{if !$0 {renamed=nil}})) {
                TextField("Title",text:$title)
                Button("Save"){if let renamed {let value=title;Task {await model.perform{try await $0.renameReading(id:renamed.id,title:value)}}};renamed=nil}
                Button("Cancel",role:.cancel){renamed=nil}
            }
    }
}

private struct SavedReadingDetailView:View {
    @Environment(AppEnvironment.self) private var model
    let id:String
    @State private var saved:SavedReading?
    @State private var error:String?
    var body:some View {
        ScrollView {
            if let saved {
                VStack(alignment:.leading,spacing:18) {
                    Text(saved.title).font(.system(.largeTitle,design:.serif))
                    PassageReadingView(passage:saved.passage)
                }.padding(22)
            } else if let error {Text(error).foregroundStyle(.red).padding()}
            else {ProgressView("Opening saved text…").padding()}
        }.navigationTitle(saved?.title ?? "Saved text")
            .task(id:id) {do {saved=try await model.openSavedReading(id)} catch {self.error=error.localizedDescription}}
    }
}
