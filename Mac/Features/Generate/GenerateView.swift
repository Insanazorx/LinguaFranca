import SwiftUI
import LinguaFrancaCore

struct GenerateView: View {
    @Environment(AppEnvironment.self) private var model
    @State private var topic = "Random"
    private var topics: [String] { model.availableTopics }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("QWEN 3.5 · ON YOUR DEVICE", systemImage: "leaf")
                            .font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(Theme.forest)
                        Text("A little reading.\nA wider world.")
                            .font(.system(.largeTitle, design: .serif).weight(.medium))
                        Text(model.settings.replacementMode == .aggressive ? "Mixed reading with Qwen3.5-2B · experimental." : "Original English, one passage at a time.")
                            .foregroundStyle(.secondary)
                    }.padding(.top, 12)
                    NavigationLink {SavedReadingsView()} label: {
                        Label("Saved readings · \(model.savedReadings.count)",systemImage:"books.vertical")
                    }.accessibilityIdentifier("saved-readings")
                    VStack(spacing: 16) {
                        HStack {
                            Picker("English level", selection: Binding(get: { model.settings.generationLevel }, set: { level in
                                var settings = model.settings
                                settings.generationLevel = level
                                Task {
                                    do { try await model.updateSettings(settings) }
                                    catch { model.errorMessage = error.localizedDescription }
                                }
                            })) {
                                ForEach(CEFRLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).frame(width: 140).disabled(model.generating)
                            Spacer()
                            Text("\(model.settings.writingGenre.title)").foregroundStyle(.secondary).font(.subheadline)
                        }
                        Divider()
                        Picker("Topic", selection: $topic) {
                            ForEach(topics, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).disabled(model.generating)
                        ReadingOptionsView(settings: Binding(get: { model.settings }, set: { settings in
                            Task {
                                do { try await model.updateSettings(settings) }
                                catch { model.errorMessage = error.localizedDescription }
                            }
                        })).disabled(model.generating)
                        if model.generating {
                            HStack {
                                ProgressView()
                                Text(model.generationPhase).font(.subheadline)
                                Spacer()
                                Button("Cancel") { model.cancelGeneration() }
                            }
                        } else {
                            Button {
                                let chosen = topic == "Random" ? topics.dropFirst().randomElement()! : topic
                                model.generate(topic: chosen)
                            } label: {
                                Label("Generate passage", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }.buttonStyle(.borderedProminent).disabled(!model.canGenerate)
                        }
                        if model.modelURL == nil {
                            Label("This development build does not yet include the offline language model.", systemImage: "info.circle")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("Written locally by Qwen3.5. No connection needed.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 24))

                    if let message = model.generationMessage {
                        Label(message, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.passages.isEmpty {
                        ContentUnavailableView("Your next good read starts here", systemImage: "book.pages",
                            description: Text("Unsaved readings last for this session. Use Save to keep a text for later reading and listening."))
                    } else {
                        Text("THIS SESSION").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        ForEach(model.passages) { passage in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(passage.metadata["title"] ?? passage.topic).font(.headline)
                                    Spacer()
                                    Text(passage.cefrLevel.rawValue).font(.caption.bold()).foregroundStyle(Theme.forest)
                                }
                                if let genre = passage.metadata["writingGenre"].flatMap(WritingGenre.init(rawValue:)) {
                                    Text(genre.title).font(.caption).foregroundStyle(.secondary)
                                }
                                if passage.metadata["replacementStatus"] == "processing", model.generating {
                                    Label("Preparing translations…",systemImage:"hourglass").font(.caption).foregroundStyle(.secondary)
                                } else if passage.metadata["replacementMode"] == "aggressive", passage.metadata["replacementComplete"] == "false" {
                                    Label("English draft · Aggressive translation is incomplete",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                                    if let missing = passage.metadata["unresolvedWords"], !missing.isEmpty {
                                        Text("Unresolved: " + missing).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                PassageReadingView(passage: passage)
                                HStack {
                                    if passage.metadata["replacementMode"] == "aggressive", let eligible = passage.metadata["eligibleWordCount"] {
                                        Text("\(passage.metadata["replacedWordCount"] ?? String(passage.replacements.count)) of \(eligible) selected expressions translated").font(.caption).foregroundStyle(.secondary)
                                    } else if let density = passage.metadata["actualDensity"].flatMap(Double.init) {
                                        Text("\(passage.replacements.count) words mixed · \(Int((density * 100).rounded()))%")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Remix", systemImage: "shuffle") { Task { await model.remix(passage) } }
                                        .font(.caption).disabled(model.remixing || model.generating)
                                        .accessibilityLabel("Remix passage with current practice settings")
                                }
                                if passage.metadata["replacementMode"] != "aggressive", let requested = passage.metadata["requestedDensity"].flatMap(Double.init),
                                   let actual = passage.metadata["actualDensity"].flatMap(Double.init), requested - actual > 0.025 {
                                    Text("Target \(Int((requested * 100).rounded()))% · words without a clear match stayed in English.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text("\(passage.modelID.contains("2B") ? "Qwen3.5-2B" : "Qwen3.5-0.8B") · \(passage.originalEnglish.split(whereSeparator: \.isWhitespace).count) words")
                                    Spacer()
                                    if let seconds = passage.metadata["durationSeconds"].flatMap(Double.init) {
                                        Text("\(seconds, specifier: "%.1f") s")
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 22))
                                .id(passage.id)
                        }
                    }
                }.padding(20)
            }.background(Theme.paper)
            .onChange(of: model.passages.first?.id) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                }
            }
            }
            .navigationTitle("LinguaFranca").inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .primaryAction) { Image(systemName: "leaf").foregroundStyle(Theme.forest).accessibilityLabel("Offline reading") } }
        }
    }
}
