import SwiftUI
import LinguaFrancaCore

struct GenerateView: View {
    @Environment(AppEnvironment.self) private var model
    @State private var topic = "Random"
    private var topics: [String] { model.availableTopics }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("QWEN 3.5 · ON YOUR DEVICE", systemImage: "leaf")
                            .font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(Theme.forest)
                        Text("A little reading.\nA wider world.")
                            .font(.system(.largeTitle, design: .serif).weight(.medium))
                        Text("Original English, one passage at a time.")
                            .foregroundStyle(.secondary)
                    }.padding(.top, 12)
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
                            Text("~\(model.settings.defaultWordCount) words").foregroundStyle(.secondary).font(.subheadline)
                        }
                        Divider()
                        Picker("Topic", selection: $topic) {
                            ForEach(topics, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).disabled(model.generating)
                        if model.generating {
                            HStack {
                                ProgressView()
                                Text("Writing on your device…").font(.subheadline)
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

                    if model.passages.isEmpty {
                        ContentUnavailableView("Your next good read starts here", systemImage: "book.pages",
                            description: Text("Generated passages will stay in your library, ready to read offline."))
                    } else {
                        Text("YOUR READING LIBRARY").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                        ForEach(model.passages) { passage in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(passage.metadata["title"] ?? passage.topic).font(.headline)
                                    Spacer()
                                    Text(passage.cefrLevel.rawValue).font(.caption.bold()).foregroundStyle(Theme.forest)
                                }
                                InteractivePassageView(passage: passage)
                                HStack {
                                    if let density = passage.metadata["actualDensity"].flatMap(Double.init) {
                                        Text("\(passage.replacements.count) words mixed · \(Int((density * 100).rounded()))%")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Remix", systemImage: "shuffle") { Task { await model.remix(passage) } }
                                        .font(.caption).disabled(model.remixing || model.generating)
                                        .accessibilityLabel("Remix passage with saved language frequencies")
                                }
                                if let requested = passage.metadata["requestedDensity"].flatMap(Double.init),
                                   let actual = passage.metadata["actualDensity"].flatMap(Double.init), requested - actual > 0.025 {
                                    Text("Target \(Int((requested * 100).rounded()))% · words without a clear match stayed in English.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text("Qwen3.5 · \(passage.metadata["wordCount"] ?? String(passage.originalEnglish.split(whereSeparator: \.isWhitespace).count)) words")
                                    Spacer()
                                    if let seconds = passage.metadata["durationSeconds"].flatMap(Double.init) {
                                        Text("\(seconds, specifier: "%.1f") s")
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                }.padding(20)
            }.background(Theme.paper)
            .navigationTitle("LinguaFranca").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Image(systemName: "leaf").foregroundStyle(Theme.forest).accessibilityLabel("Offline reading") } }
        }
    }
}
