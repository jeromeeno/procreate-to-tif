import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isEventLogExpanded = false
    private let logBottomID = "event-log-bottom"
    private let exportColumnWidth: CGFloat = 30

    var body: some View {
        NavigationSplitView {
            List {
                Section("Output") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.outputDirectoryURL.path)
                            .font(.callout)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                            .help(viewModel.outputDirectoryURL.path)
                        Button("Choose Output Folder…") {
                            viewModel.chooseOutputDirectory()
                        }
                        Toggle("Play completion sound", isOn: $viewModel.completionSoundEnabled)
                        HStack(spacing: 8) {
                            Picker("Completion Sound", selection: $viewModel.completionSoundChoiceID) {
                                ForEach(viewModel.completionSoundChoices) { choice in
                                    Text(choice.title).tag(choice.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(!viewModel.completionSoundEnabled)

                            Button("Preview") {
                                viewModel.previewCompletionSound()
                            }
                            .disabled(!viewModel.completionSoundEnabled)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Export Options") {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Formats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Layered PSD", isOn: $viewModel.options.writePSD)
                            Toggle("Flat PNG", isOn: $viewModel.options.writeFlatPNG)
                            Toggle("Flat JPG", isOn: $viewModel.options.writeFlatJPG)
                            HStack {
                                Text("JPG Quality")
                                Spacer()
                                Text("\(viewModel.options.normalizedJPGQuality)")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.options.jpgQuality) },
                                    set: { viewModel.options.jpgQuality = Int($0.rounded()) }
                                ),
                                in: 1 ... 100,
                                step: 1
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Animation & Timelapse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Animated WebP", isOn: $viewModel.options.writeAnimatedWebP)
                            Toggle("Animated GIF", isOn: $viewModel.options.writeAnimatedGIF)
                            Toggle("Timelapse MP4", isOn: $viewModel.options.writeTimelapseMP4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }

                Section("Preview") {
                    previewPanel
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 390, ideal: 430, max: 520)
            .navigationTitle("Conversion Setup")
        } detail: {
            VStack(alignment: .leading, spacing: 14) {
                fileList
                progress
                logs
            }
            .padding(16)
            .navigationTitle("ProArchive Converter")
            .dropDestination(for: URL.self) { dropped, _ in
                viewModel.addInputFiles(dropped, source: .drop)
                return true
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Add Files…") {
                    viewModel.chooseInputFiles()
                }

                Button("Remove Selected") {
                    viewModel.removeSelectedInputFiles()
                }
                .disabled(viewModel.selectedInputFiles.isEmpty || viewModel.isRunning)

                Button("Clear") {
                    viewModel.clearInputs()
                }
                .disabled(viewModel.inputFiles.isEmpty || viewModel.isRunning)
            }

            ToolbarItem {
                if viewModel.isRunning {
                    Button("Stop Process") {
                        viewModel.stopConversion()
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(viewModel.isRunning ? "Running…" : "Convert") {
                    viewModel.runConversion()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canRun)
            }
        }
    }

    private var fileList: some View {
        GroupBox("Inputs (\(viewModel.inputFiles.count))") {
            List(selection: $viewModel.selectedInputFiles) {
                Section {
                    ForEach(viewModel.inputFiles, id: \.self) { url in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .foregroundStyle(.secondary)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(ExportKind.allCases, id: \.self) { kind in
                                exportStatusIcon(viewModel.exportProgress(for: url, kind: kind))
                                    .frame(width: exportColumnWidth)
                            }
                        }
                        .tag(url)
                    }
                    .onDelete(perform: viewModel.removeInputFiles)
                } header: {
                    inputStatusHeader
                        .textCase(nil)
                }
            }
            .frame(minHeight: 220)
        }
    }

    private var inputStatusHeader: some View {
        HStack(spacing: 8) {
            Text("File")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(ExportKind.allCases, id: \.self) { kind in
                Text(kind.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: exportColumnWidth)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func exportStatusIcon(_ status: ExportProgressState) -> some View {
        switch status {
        case .notEnabled:
            Circle()
                .fill(Color.gray.opacity(0.18))
                .frame(width: 6, height: 6)
        case .pending:
            Image(systemName: "circle.fill")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.gray.opacity(0.7))
        case .inProgress:
            Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "arrow.uturn.right.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.yellow)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected = viewModel.selectedInputFile {
                Text(selected.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                if let image = viewModel.selectedInputPreviewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Text(viewModel.selectedInputPreviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(10)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .padding(.vertical, 2)
    }

    private var progress: some View {
        GroupBox("Progress") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: viewModel.progressFraction)
                Text(viewModel.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if viewModel.awaitingCompletionAcknowledgement && !viewModel.isRunning {
                    HStack(spacing: 10) {
                        Button("Open Output Folder") {
                            viewModel.openOutputDirectory()
                        }
                        Button("Reset Queue") {
                            viewModel.resetQueue()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logs: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isEventLogExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isEventLogExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Event Log")
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Open Log Folder") {
                        viewModel.openLogDirectory()
                    }
                    .disabled(!viewModel.canOpenLogDirectory)

                    Button("Copy Logs") {
                        viewModel.copyLogsToClipboard()
                    }
                    .disabled(viewModel.logLines.isEmpty)
                }

                if isEventLogExpanded {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(viewModel.logText)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                Color.clear
                                    .frame(height: 1)
                                    .id(logBottomID)
                            }
                        }
                        .frame(minHeight: 180)
                        .onAppear {
                            scrollLogsToBottom(proxy: proxy, animated: false)
                        }
                        .onChange(of: viewModel.logLines.count) { _ in
                            scrollLogsToBottom(proxy: proxy, animated: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scrollLogsToBottom(proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(logBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(logBottomID, anchor: .bottom)
            }
        }
    }
}
