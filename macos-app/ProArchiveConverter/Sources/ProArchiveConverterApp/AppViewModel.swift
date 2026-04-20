import AppKit
import Foundation
import ProcreateBridgeCore
import UniformTypeIdentifiers

enum ExportKind: String, CaseIterable, Hashable, Sendable {
    case psd
    case png
    case jpg
    case webp
    case gif
    case mp4

    var label: String {
        rawValue.uppercased()
    }

    var outputKey: String {
        rawValue
    }

    func outputFilename(for stem: String) -> String {
        switch self {
        case .psd:
            "\(stem).psd"
        case .png:
            "\(stem).png"
        case .jpg:
            "\(stem).jpg"
        case .webp:
            "\(stem).webp"
        case .gif:
            "\(stem).gif"
        case .mp4:
            "\(stem).timelapse.mp4"
        }
    }

    func isEnabled(in options: ConversionOptions) -> Bool {
        switch self {
        case .psd:
            options.writePSD
        case .png:
            options.writeFlatPNG
        case .jpg:
            options.writeFlatJPG
        case .webp:
            options.writeAnimatedWebP
        case .gif:
            options.writeAnimatedGIF
        case .mp4:
            options.writeTimelapseMP4
        }
    }
}

enum ExportProgressState: Sendable, Equatable {
    case notEnabled
    case pending
    case inProgress
    case completed
    case skipped
    case failed
}

struct CompletionSoundChoice: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let fileURL: URL?
}

@MainActor
final class AppViewModel: ObservableObject {
    enum InputAddSource {
        case drop
        case picker
        case other
    }

    @Published var backendExecutablePath: String
    @Published var outputDirectoryURL: URL
    @Published var options: ConversionOptions {
        didSet {
            if !isRunning {
                refreshExportProgressForCurrentInputs()
            }
        }
    }
    @Published var inputFiles: [URL] = []
    @Published var selectedInputFiles: Set<URL> = [] {
        didSet {
            syncPrimarySelectionFromSet()
        }
    }
    @Published var selectedInputFile: URL? {
        didSet {
            if oldValue?.standardizedFileURL != selectedInputFile?.standardizedFileURL {
                loadSelectedInputPreview()
            }
        }
    }
    @Published var selectedInputPreviewImage: NSImage?
    @Published var selectedInputPreviewText = "Select an input file to preview."

    @Published var isRunning = false
    @Published var progressFraction = 0.0
    @Published var statusText = "Idle"
    @Published var logLines: [String] = []
    @Published var logText = ""
    @Published var completionSoundEnabled = true {
        didSet {
            UserDefaults.standard.set(completionSoundEnabled, forKey: Self.completionSoundDefaultsKey)
        }
    }
    @Published var completionSoundChoiceID: String {
        didSet {
            UserDefaults.standard.set(completionSoundChoiceID, forKey: Self.completionSoundChoiceDefaultsKey)
        }
    }
    @Published var awaitingCompletionAcknowledgement = false
    @Published private var exportProgressByFile: [URL: [ExportKind: ExportProgressState]] = [:]
    private let runner = ConverterProcessRunner()
    private let logTimestampFormatter: DateFormatter
    let completionSoundChoices: [CompletionSoundChoice]

    private var didReceiveRunComplete = false
    private var stopRequested = false
    private var runStartedAt: Date?
    private var perFileStartedAt: [String: Date] = [:]
    private var completedFileCount = 0
    private var accumulatedFileDuration: TimeInterval = 0
    private var previewLoadToken = UUID()
    private var previewCache: [URL: NSImage] = [:]
    private var unavailablePreviews: Set<URL> = []
    private var activeCompletionSound: NSSound?
    private var logBuffer: [String] = []
    private var logFlushWorkItem: DispatchWorkItem?
    private var exportProgressWorking: [URL: [ExportKind: ExportProgressState]] = [:]
    private var exportProgressFlushWorkItem: DispatchWorkItem?
    private let autosaveLogDirectoryURL: URL?
    private let autosaveLogFileURL: URL?
    private let autosaveSetupWarning: String?
    private var didReportAutosaveWriteFailure = false

    private static let outputDirectoryDefaultsKey = "proarchive.outputDirectoryPath"
    private static let completionSoundDefaultsKey = "proarchive.playCompletionSound"
    private static let completionSoundChoiceDefaultsKey = "proarchive.completionSoundChoice"
    private static let uiFlushInterval: TimeInterval = 0.12
    private static let maxRetainedLogLines = 4_000
    private static let autosaveLogDirectoryName = "ProArchiveConverter"

    private struct ExistingOutputScan {
        let existingPaths: [URL]
        let affectedInputCount: Int

        var existingFileCount: Int {
            existingPaths.count
        }
    }

    private struct LogAutosaveSetup {
        let directoryURL: URL?
        let fileURL: URL?
        let warningMessage: String?
    }

    private enum ExistingOutputDecision {
        case overwriteAll
        case skipExisting
        case cancel
    }

    init() {
        let timestampFormatter = DateFormatter()
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.dateFormat = "HH:mm:ss.SSS"
        self.logTimestampFormatter = timestampFormatter

        if let defaultExecutable = Self.defaultBackendExecutableURL() {
            self.backendExecutablePath = defaultExecutable.path
        } else {
            self.backendExecutablePath = ""
        }

        self.outputDirectoryURL = Self.initialOutputDirectoryURL()
        self.options = ConversionOptions()
        let autosaveSetup = Self.prepareAutosaveLogFile()
        self.autosaveLogDirectoryURL = autosaveSetup.directoryURL
        self.autosaveLogFileURL = autosaveSetup.fileURL
        self.autosaveSetupWarning = autosaveSetup.warningMessage
        self.completionSoundChoices = Self.discoverCompletionSoundChoices()
        self.completionSoundEnabled = UserDefaults.standard.object(forKey: Self.completionSoundDefaultsKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.completionSoundDefaultsKey)
        self.completionSoundChoiceID = Self.initialCompletionSoundChoiceID(choices: completionSoundChoices)
        refreshExportProgressForCurrentInputs()
    }

    var canRun: Bool {
        !isRunning && !inputFiles.isEmpty && !backendExecutablePath.isEmpty
    }

    func exportProgress(for file: URL, kind: ExportKind) -> ExportProgressState {
        let key = file.standardizedFileURL
        if let status = exportProgressByFile[key]?[kind] {
            return status
        }
        return kind.isEnabled(in: options) ? .pending : .notEnabled
    }

    func addInputFiles(_ urls: [URL], source: InputAddSource = .other) {
        let filtered = Self.collectProcreateInputURLs(from: urls, source: source)
        guard !filtered.isEmpty else {
            appendLog("No .procreate files detected in selection.")
            return
        }

        var merged = inputFiles
        for url in filtered {
            let standardized = url.standardizedFileURL
            if !merged.contains(where: { $0.standardizedFileURL == standardized }) {
                merged.append(standardized)
            }
        }
        inputFiles = merged.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        if selectedInputFiles.isEmpty, let first = inputFiles.first?.standardizedFileURL {
            selectedInputFiles = [first]
        } else {
            let valid = Set(inputFiles.map(\.standardizedFileURL))
            selectedInputFiles = Set(selectedInputFiles.map(\.standardizedFileURL)).intersection(valid)
            if selectedInputFiles.isEmpty, let first = inputFiles.first?.standardizedFileURL {
                selectedInputFiles = [first]
            }
        }
        refreshExportProgressForCurrentInputs()
    }

    private static func collectProcreateInputURLs(from urls: [URL], source: InputAddSource) -> [URL] {
        let fileManager = FileManager.default
        var discovered: [URL] = []
        var seenPaths: Set<String> = []
        var droppedProcreateByParent: [URL: Set<String>] = [:]
        var droppedDirectories: Set<URL> = []

        func appendIfNeeded(_ url: URL) {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard seenPaths.insert(path).inserted else {
                return
            }
            discovered.append(standardized)
        }

        for root in urls {
            let standardizedRoot = root.standardizedFileURL
            if standardizedRoot.pathExtension.caseInsensitiveCompare("procreate") == .orderedSame {
                appendIfNeeded(standardizedRoot)
                let parent = standardizedRoot.deletingLastPathComponent().standardizedFileURL
                droppedProcreateByParent[parent, default: []].insert(standardizedRoot.path)
                continue
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            droppedDirectories.insert(standardizedRoot)

            guard let enumerator = fileManager.enumerator(
                at: standardizedRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let itemURL as URL in enumerator {
                let standardizedItem = itemURL.standardizedFileURL
                guard standardizedItem.pathExtension.caseInsensitiveCompare("procreate") == .orderedSame else {
                    continue
                }
                appendIfNeeded(standardizedItem)
            }
        }

        if source == .drop {
            for (parent, droppedSet) in droppedProcreateByParent {
                guard !droppedDirectories.contains(parent) else {
                    continue
                }

                let topLevelPaths = Set(topLevelProcreatePaths(in: parent, fileManager: fileManager))
                guard !topLevelPaths.isEmpty, droppedSet == topLevelPaths else {
                    continue
                }

                appendNestedProcreateFiles(in: parent, fileManager: fileManager, appendIfNeeded: appendIfNeeded)
            }
        }

        return discovered
    }

    private static func topLevelProcreatePaths(in directory: URL, fileManager: FileManager) -> [String] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { child in
            let standardized = child.standardizedFileURL
            guard standardized.pathExtension.caseInsensitiveCompare("procreate") == .orderedSame else {
                return nil
            }
            return standardized.path
        }
    }

    private static func appendNestedProcreateFiles(
        in directory: URL,
        fileManager: FileManager,
        appendIfNeeded: (URL) -> Void
    ) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for case let itemURL as URL in enumerator {
            let standardizedItem = itemURL.standardizedFileURL
            guard standardizedItem.pathExtension.caseInsensitiveCompare("procreate") == .orderedSame else {
                continue
            }
            if standardizedItem.deletingLastPathComponent().standardizedFileURL != directory {
                appendIfNeeded(standardizedItem)
            }
        }
    }

    func removeInputFiles(at offsets: IndexSet) {
        let removed = Set(offsets.map { inputFiles[$0].standardizedFileURL })
        inputFiles.remove(atOffsets: offsets)
        selectedInputFiles.subtract(removed)
        if selectedInputFiles.isEmpty, let first = inputFiles.first?.standardizedFileURL {
            selectedInputFiles = [first]
        }
        refreshExportProgressForCurrentInputs()
    }

    func removeSelectedInputFiles() {
        var targets = Set(selectedInputFiles.map(\.standardizedFileURL))
        if targets.isEmpty, let selected = selectedInputFile?.standardizedFileURL {
            targets.insert(selected)
        }
        guard !targets.isEmpty else {
            return
        }
        inputFiles.removeAll { targets.contains($0.standardizedFileURL) }
        selectedInputFiles.removeAll()
        if let first = inputFiles.first?.standardizedFileURL {
            selectedInputFiles = [first]
        }
        refreshExportProgressForCurrentInputs()
    }

    func clearInputs() {
        inputFiles.removeAll()
        selectedInputFiles.removeAll()
        selectedInputFile = nil
        refreshExportProgressForCurrentInputs()
    }

    func chooseInputFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if let procreateType = UTType(filenameExtension: "procreate") {
            panel.allowedContentTypes = [procreateType]
        }
        panel.message = "Choose one or more .procreate files."

        guard panel.runModal() == .OK else {
            return
        }
        addInputFiles(panel.urls, source: .picker)
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select an output folder."
        panel.directoryURL = outputDirectoryURL

        guard panel.runModal() == .OK, let selected = panel.urls.first else {
            return
        }
        let standardized = selected.standardizedFileURL
        outputDirectoryURL = standardized
        persistOutputDirectory(standardized)
    }

    func runConversion() {
        if backendExecutablePath.isEmpty, let resolvedExecutable = Self.defaultBackendExecutableURL() {
            backendExecutablePath = resolvedExecutable.path
        }

        guard canRun else {
            if backendExecutablePath.isEmpty {
                appendLog("Cannot start run: backend executable not found.")
            } else {
                appendLog("Cannot start run: add at least one .procreate input file.")
            }
            return
        }

        var runOptions = options
        let scan = scanExistingOutputs(inputFiles: inputFiles, outputDirectoryURL: outputDirectoryURL, options: runOptions)
        if scan.existingFileCount > 0 {
            appendLog(
                "Detected \(scan.existingFileCount) existing output file(s) across \(scan.affectedInputCount) input file(s)."
            )
            switch promptForExistingOutputDecision(scan: scan) {
            case .overwriteAll:
                runOptions.existingOutputBehavior = .overwrite
                appendLog("Existing outputs: user selected Overwrite All.")
            case .skipExisting:
                runOptions.existingOutputBehavior = .skip
                appendLog("Existing outputs: user selected Skip Existing.")
            case .cancel:
                appendLog("Conversion cancelled before launch due to existing outputs.")
                statusText = "Idle"
                return
            }
        }

        let invocation = ConverterInvocation(
            executableURL: URL(fileURLWithPath: backendExecutablePath),
            inputFiles: inputFiles,
            outputDirectoryURL: outputDirectoryURL,
            options: runOptions
        )
        startConversion(invocation)
    }

    private func startConversion(_ invocation: ConverterInvocation) {
        let executableURL = invocation.executableURL
        let runner = self.runner

        isRunning = true
        progressFraction = 0
        statusText = "Starting conversion..."
        resetLogState()
        if let autosaveLogFileURL {
            appendLog("Autosaving logs to \(autosaveLogFileURL.path)")
        } else if let autosaveSetupWarning {
            appendLog("Log autosave unavailable: \(autosaveSetupWarning)")
        }
        awaitingCompletionAcknowledgement = false
        didReceiveRunComplete = false
        stopRequested = false
        resetRunExportProgress()
        runStartedAt = Date()
        perFileStartedAt.removeAll(keepingCapacity: true)
        completedFileCount = 0
        accumulatedFileDuration = 0
        appendLog("Launching: \(executableURL.path)")
        appendLog("Arguments: \(renderCommandArguments(invocation.arguments))")

        Task.detached {
            do {
                let result = try runner.run(invocation: invocation) { event in
                    Task { @MainActor in
                        self.consume(event: event)
                    }
                }

                await MainActor.run {
                    if !result.stderr.isEmpty {
                        self.appendLog("stderr: \(result.stderr)")
                    }
                    if result.terminatedBySignal {
                        if self.stopRequested {
                            self.appendLog("Conversion stopped by user.")
                            self.statusText = "Conversion stopped."
                        } else {
                            self.appendLog("Process terminated by signal \(result.exitCode).")
                            self.statusText = "Conversion interrupted (signal \(result.exitCode))."
                        }
                    } else {
                        self.statusText = result.exitCode == 0 ? "Conversion complete." : "Conversion failed (exit \(result.exitCode))."
                    }
                    if !self.didReceiveRunComplete {
                        self.appendLog("Run ended before run_complete event was received.")
                        self.markInterruptedRunProgress()
                    }
                    self.isRunning = false
                    self.stopRequested = false
                    self.awaitingCompletionAcknowledgement = true
                    self.flushPendingUIUpdates()
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Runner error: \(error.localizedDescription)")
                    self.statusText = "Run failed."
                    self.isRunning = false
                    self.stopRequested = false
                    self.markInterruptedRunProgress()
                    self.awaitingCompletionAcknowledgement = true
                    self.flushPendingUIUpdates()
                }
            }
        }
    }

    private func scanExistingOutputs(
        inputFiles: [URL],
        outputDirectoryURL: URL,
        options: ConversionOptions
    ) -> ExistingOutputScan {
        let fileManager = FileManager.default
        let selectedKinds = Set(ExportKind.allCases.filter { $0.isEnabled(in: options) })
        var existingPaths: [URL] = []
        var seenPaths: Set<String> = []
        var affectedInputCount = 0

        for inputFile in inputFiles {
            let stem = inputFile.deletingPathExtension().lastPathComponent
            var hasConflict = false

            for kind in selectedKinds {
                let outputPath = outputDirectoryURL.appendingPathComponent(kind.outputFilename(for: stem), isDirectory: false)
                guard fileManager.fileExists(atPath: outputPath.path) else {
                    continue
                }

                hasConflict = true
                let normalizedPath = outputPath.standardizedFileURL.path
                if seenPaths.insert(normalizedPath).inserted {
                    existingPaths.append(outputPath.standardizedFileURL)
                }
            }

            if hasConflict {
                affectedInputCount += 1
            }
        }

        existingPaths.sort { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        return ExistingOutputScan(existingPaths: existingPaths, affectedInputCount: affectedInputCount)
    }

    private func promptForExistingOutputDecision(scan: ExistingOutputScan) -> ExistingOutputDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Existing export files found"

        let sampleLimit = 6
        let samples = scan.existingPaths.prefix(sampleLimit).map(\.lastPathComponent)
        var details = [
            "Found \(scan.existingFileCount) existing output file(s) across \(scan.affectedInputCount) input file(s).",
            "Choose one action for all conflicts.",
        ]
        if !samples.isEmpty {
            details.append("")
            details.append("Examples:")
            details.append(contentsOf: samples.map { "- \($0)" })
            let remaining = scan.existingFileCount - samples.count
            if remaining > 0 {
                details.append("- ...and \(remaining) more")
            }
        }

        alert.informativeText = details.joined(separator: "\n")
        alert.addButton(withTitle: "Overwrite All")
        alert.addButton(withTitle: "Skip Existing")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .overwriteAll
        case .alertSecondButtonReturn:
            return .skipExisting
        default:
            return .cancel
        }
    }

    func stopConversion() {
        guard isRunning else {
            return
        }

        stopRequested = true
        statusText = "Stopping..."
        appendLog("Stop requested. Sending SIGTERM to converter process.")
        runner.terminateCurrentProcess()
    }

    func copyLogsToClipboard() {
        scheduleLogFlush(immediate: true)
        guard !logLines.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
    }

    func openOutputDirectory() {
        do {
            try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        } catch {
            appendLog("Could not open output folder: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(outputDirectoryURL)
    }

    var canOpenLogDirectory: Bool {
        autosaveLogDirectoryURL != nil
    }

    func openLogDirectory() {
        guard let autosaveLogDirectoryURL else {
            appendLog("Could not open log folder: autosave path is unavailable.")
            return
        }

        do {
            try FileManager.default.createDirectory(at: autosaveLogDirectoryURL, withIntermediateDirectories: true)
        } catch {
            appendLog("Could not open log folder: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(autosaveLogDirectoryURL)
    }

    func resetQueue() {
        guard awaitingCompletionAcknowledgement, !isRunning else {
            return
        }
        awaitingCompletionAcknowledgement = false
        progressFraction = 0
        statusText = "Idle"
        appendLog("Queue reset. Ready for next conversion.")
    }

    func previewCompletionSound() {
        playSelectedCompletionSound()
    }

    private func loadSelectedInputPreview() {
        guard let selected = selectedInputFile?.standardizedFileURL else {
            selectedInputPreviewImage = nil
            selectedInputPreviewText = "Select an input file to preview."
            return
        }

        if let cached = previewCache[selected] {
            selectedInputPreviewImage = cached
            selectedInputPreviewText = selected.lastPathComponent
            return
        }
        if unavailablePreviews.contains(selected) {
            selectedInputPreviewImage = nil
            selectedInputPreviewText = "Preview not available for \(selected.lastPathComponent)."
            return
        }

        selectedInputPreviewImage = nil
        selectedInputPreviewText = "Loading preview for \(selected.lastPathComponent)…"
        let token = UUID()
        previewLoadToken = token

        Task.detached(priority: .userInitiated) {
            let image = Self.loadThumbnailImage(from: selected)
            await MainActor.run {
                guard self.previewLoadToken == token else {
                    return
                }

                if let image {
                    self.previewCache[selected] = image
                    self.selectedInputPreviewImage = image
                    self.selectedInputPreviewText = selected.lastPathComponent
                } else {
                    self.unavailablePreviews.insert(selected)
                    self.selectedInputPreviewImage = nil
                    self.selectedInputPreviewText = "Preview not available for \(selected.lastPathComponent)."
                }
            }
        }
    }

    private func syncPrimarySelectionFromSet() {
        let valid = Set(inputFiles.map(\.standardizedFileURL))
        let normalizedSelection = Set(selectedInputFiles.map(\.standardizedFileURL)).intersection(valid)
        if normalizedSelection != selectedInputFiles {
            selectedInputFiles = normalizedSelection
            return
        }

        if let current = selectedInputFile?.standardizedFileURL, normalizedSelection.contains(current) {
            return
        }

        selectedInputFile = inputFiles.first(where: { normalizedSelection.contains($0.standardizedFileURL) })?.standardizedFileURL
    }

    private nonisolated static func loadThumbnailImage(from fileURL: URL) -> NSImage? {
        let candidates = [
            "QuickLook/Thumbnail.png",
            "QuickLook/Preview.png",
            "QuickLook/Thumbnail.jpg",
            "QuickLook/Preview.jpg",
        ]

        if let image = loadThumbnailImageFromFilesystem(fileURL: fileURL, candidates: candidates) {
            return image
        }

        for path in candidates {
            guard let data = readZipEntry(fileURL: fileURL, entryPath: path) else {
                continue
            }
            if let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    private nonisolated static func loadThumbnailImageFromFilesystem(fileURL: URL, candidates: [String]) -> NSImage? {
        let fileManager = FileManager.default
        var roots: [URL] = []

        if fileManager.fileExists(atPath: fileURL.path, isDirectory: nil) {
            roots.append(fileURL)
        }

        let siblingFolder = fileURL.deletingPathExtension()
        if siblingFolder != fileURL {
            roots.append(siblingFolder)
        }

        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            for candidate in candidates {
                let candidateURL = root.appending(path: candidate, directoryHint: .notDirectory)
                guard fileManager.fileExists(atPath: candidateURL.path) else {
                    continue
                }
                if let image = NSImage(contentsOf: candidateURL) {
                    return image
                }
            }
        }

        return nil
    }

    private nonisolated static func readZipEntry(fileURL: URL, entryPath: String) -> Data? {
        let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
        guard FileManager.default.isExecutableFile(atPath: unzip.path) else {
            return nil
        }

        let process = Process()
        process.executableURL = unzip
        process.arguments = ["-p", fileURL.path, entryPath]
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        // Drain stdout while unzip runs; waiting first can deadlock on large thumbnails.
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        return data.isEmpty ? nil : data
    }

    private func consume(event: ConversionLogEvent) {
        switch event {
        case let .runStart(total):
            statusText = "Queued \(total) file(s)."
            progressFraction = 0
            appendLog("Run started (\(total) file(s)).")
        case let .fileStart(file, index, total):
            let name = URL(fileURLWithPath: file).lastPathComponent
            markFileStarted(file: file)
            perFileStartedAt[file] = Date()
            statusText = "Converting \(index)/\(total): \(name)"
            appendLog("Starting \(index)/\(total): \(name)")
        case let .fileOutput(file, index, total, output, status, path, message):
            markOutputState(file: file, output: output, status: status)
            let name = URL(fileURLWithPath: file).lastPathComponent
            let outputLabel = output.uppercased()
            let messageSuffix = message.map { " (\($0))" } ?? ""
            let pathSuffix = path.map { " [\($0)]" } ?? ""
            switch status {
            case "started":
                appendLog("Output \(index)/\(total): \(name) \(outputLabel) started\(pathSuffix).")
            case "completed":
                appendLog("Output \(index)/\(total): \(name) \(outputLabel) completed\(pathSuffix).")
            case "skipped":
                appendLog("Output \(index)/\(total): \(name) \(outputLabel) skipped\(messageSuffix)\(pathSuffix).")
            case "failed":
                appendLog("Output \(index)/\(total): \(name) \(outputLabel) failed\(messageSuffix)\(pathSuffix).")
            default:
                appendLog("Output \(index)/\(total): \(name) \(outputLabel) \(status)\(messageSuffix)\(pathSuffix).")
            }
        case let .fileSuccess(file, index, total, width, height, layerCount, outputs, skipped):
            let name = URL(fileURLWithPath: file).lastPathComponent
            let outputKinds = outputs.keys.sorted().joined(separator: ", ")
            let skippedText = skipped.isEmpty ? "" : " | skipped: \(skipped.joined(separator: ", "))"
            let timingText = timingSuffix(for: file)
            progressFraction = total > 0 ? Double(index) / Double(total) : 0
            statusText = "Completed \(index)/\(total)."
            markFileFinished(file: file, outputs: outputs, skipped: skipped)
            appendLog(
                "Finished \(index)/\(total): \(name) (\(width)x\(height), \(layerCount) layers) | outputs: \(outputKinds)\(skippedText)\(timingText)"
            )
        case let .fileError(file, index, total, message, errorCode):
            let name = URL(fileURLWithPath: file).lastPathComponent
            let timingText = timingSuffix(for: file)
            progressFraction = total > 0 ? Double(index) / Double(total) : 0
            statusText = "Error on \(index)/\(total)."
            markFileFailed(file: file)
            appendLog("Error \(index)/\(total): \(name) [\(errorCode)] \(message)\(timingText)")
        case let .runComplete(total, successes, failures):
            didReceiveRunComplete = true
            progressFraction = total > 0 ? Double(successes) / Double(total) : 1
            statusText = "Done: \(successes) success, \(failures) failure."
            let elapsedText = runStartedAt.map { " | elapsed: \(formatDuration(Date().timeIntervalSince($0)))" } ?? ""
            let averageText = completedFileCount > 0
                ? " | avg/file: \(formatDuration(accumulatedFileDuration / Double(completedFileCount)))"
                : ""
            appendLog("Run complete: \(successes) success / \(failures) failure / \(total) total.\(elapsedText)\(averageText)")
            appendPerFormatSummary()
            if completionSoundEnabled {
                playSelectedCompletionSound()
            }
        case let .unknown(name, rawLine):
            appendLog("Unknown event: \(name) | raw: \(rawLine)")
        case let .malformed(rawLine):
            appendLog("Malformed line: \(rawLine)")
        }
    }

    private func appendLog(_ line: String) {
        let timestamp = logTimestampFormatter.string(from: Date())
        logBuffer.append("[\(timestamp)] \(line)")
        scheduleLogFlush()
    }

    private func resetLogState() {
        logFlushWorkItem?.cancel()
        logFlushWorkItem = nil
        logBuffer.removeAll(keepingCapacity: true)
        logLines.removeAll(keepingCapacity: true)
        logText = ""
    }

    private func scheduleLogFlush(immediate: Bool = false) {
        if immediate {
            logFlushWorkItem?.cancel()
            logFlushWorkItem = nil
            flushLogBuffer()
            return
        }

        guard logFlushWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.logFlushWorkItem = nil
            self.flushLogBuffer()
        }
        logFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.uiFlushInterval, execute: workItem)
    }

    private func flushLogBuffer() {
        guard !logBuffer.isEmpty else {
            return
        }

        let chunk = logBuffer
        logBuffer.removeAll(keepingCapacity: true)
        appendToAutosaveLog(chunk)
        logLines.append(contentsOf: chunk)

        if logLines.count > Self.maxRetainedLogLines {
            let overflow = logLines.count - Self.maxRetainedLogLines
            logLines.removeFirst(overflow)
            logText = logLines.joined(separator: "\n")
            return
        }

        let chunkText = chunk.joined(separator: "\n")
        if logText.isEmpty {
            logText = chunkText
        } else {
            logText += "\n\(chunkText)"
        }
    }

    private func appendToAutosaveLog(_ lines: [String]) {
        guard let autosaveLogFileURL else {
            return
        }

        let chunkText = lines.joined(separator: "\n")
        guard !chunkText.isEmpty, let data = "\(chunkText)\n".data(using: .utf8) else {
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: autosaveLogFileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            guard !didReportAutosaveWriteFailure else {
                return
            }
            didReportAutosaveWriteFailure = true
            appendLog("Warning: failed to autosave logs (\(error.localizedDescription)).")
        }
    }

    private func flushPendingUIUpdates() {
        scheduleLogFlush(immediate: true)
        scheduleExportProgressFlush(immediate: true)
    }

    private func renderCommandArguments(_ arguments: [String]) -> String {
        arguments.map { argument in
            if argument.contains(where: { $0.isWhitespace }) {
                return "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return argument
        }.joined(separator: " ")
    }

    private func timingSuffix(for file: String) -> String {
        guard let startedAt = perFileStartedAt.removeValue(forKey: file) else {
            return ""
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        completedFileCount += 1
        accumulatedFileDuration += elapsed
        let average = accumulatedFileDuration / Double(completedFileCount)
        return " | time: \(formatDuration(elapsed)) | avg: \(formatDuration(average))"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String(format: "%.0fms", interval * 1_000)
        }
        if interval < 60 {
            return String(format: "%.2fs", interval)
        }
        let minutes = Int(interval) / 60
        let seconds = interval - Double(minutes * 60)
        return String(format: "%dm %.1fs", minutes, seconds)
    }

    private func appendPerFormatSummary() {
        let selectedKinds = selectedExportKinds()
        guard !selectedKinds.isEmpty else {
            return
        }

        let sortedKinds = ExportKind.allCases.filter { selectedKinds.contains($0) }
        var parts: [String] = []

        for kind in sortedKinds {
            var completed = 0
            var skipped = 0
            var failed = 0

            for file in inputFiles {
                let state = exportProgress(for: file, kind: kind)
                switch state {
                case .completed:
                    completed += 1
                case .skipped:
                    skipped += 1
                case .failed:
                    failed += 1
                default:
                    break
                }
            }

            parts.append("\(kind.label): \(completed) done, \(skipped) skipped, \(failed) failed")
        }

        appendLog("Per-format summary -> \(parts.joined(separator: " | "))")
    }

    private func playSelectedCompletionSound() {
        let selected = completionSoundChoices.first(where: { $0.id == completionSoundChoiceID })
        if let fileURL = selected?.fileURL,
           let sound = NSSound(contentsOf: fileURL, byReference: false) {
            activeCompletionSound = sound
            sound.play()
            return
        }
        activeCompletionSound = nil
        NSSound.beep()
    }

    private func selectedExportKinds() -> Set<ExportKind> {
        Set(ExportKind.allCases.filter { $0.isEnabled(in: options) })
    }

    private func refreshExportProgressForCurrentInputs() {
        let selectedKinds = selectedExportKinds()
        var updated: [URL: [ExportKind: ExportProgressState]] = [:]

        for file in inputFiles {
            let key = file.standardizedFileURL
            var row: [ExportKind: ExportProgressState] = [:]
            for kind in ExportKind.allCases {
                let existing = exportProgressWorking[key]?[kind]
                if !selectedKinds.contains(kind) {
                    row[kind] = .notEnabled
                } else if let existing, existing == .completed || existing == .skipped || existing == .failed || existing == .inProgress {
                    row[kind] = existing
                } else {
                    row[kind] = .pending
                }
            }
            updated[key] = row
        }

        exportProgressWorking = updated
        scheduleExportProgressFlush(immediate: true)
    }

    private func resetRunExportProgress() {
        let selectedKinds = selectedExportKinds()
        var updated: [URL: [ExportKind: ExportProgressState]] = [:]

        for file in inputFiles {
            let key = file.standardizedFileURL
            var row: [ExportKind: ExportProgressState] = [:]
            for kind in ExportKind.allCases {
                row[kind] = selectedKinds.contains(kind) ? .pending : .notEnabled
            }
            updated[key] = row
        }

        exportProgressWorking = updated
        scheduleExportProgressFlush(immediate: true)
    }

    private func markFileStarted(file: String) {
        let key = URL(fileURLWithPath: file).standardizedFileURL
        var row = exportProgressWorking[key] ?? [:]
        for kind in ExportKind.allCases {
            guard row[kind] != .notEnabled else {
                continue
            }
            row[kind] = .pending
        }
        exportProgressWorking[key] = row
        scheduleExportProgressFlush()
    }

    private func markOutputState(file: String, output: String, status: String) {
        guard let kind = ExportKind(rawValue: output.lowercased()) else {
            return
        }

        let key = URL(fileURLWithPath: file).standardizedFileURL
        var row = exportProgressWorking[key] ?? [:]
        guard row[kind] != .notEnabled else {
            return
        }

        switch status {
        case "started":
            row[kind] = .inProgress
        case "completed":
            row[kind] = .completed
        case "skipped":
            row[kind] = .skipped
        case "failed":
            row[kind] = .failed
        default:
            break
        }
        exportProgressWorking[key] = row
        scheduleExportProgressFlush()
    }

    private func markFileFinished(file: String, outputs: [String: String], skipped: [String]) {
        let key = URL(fileURLWithPath: file).standardizedFileURL
        var row = exportProgressWorking[key] ?? [:]
        let produced = Set(outputs.keys)
        let skippedSet = Set(skipped)

        for kind in ExportKind.allCases {
            guard row[kind] != .notEnabled else {
                continue
            }
            if produced.contains(kind.outputKey) {
                row[kind] = .completed
            } else if skippedSet.contains(kind.outputKey) {
                row[kind] = .skipped
            } else if row[kind] == .inProgress || row[kind] == .pending {
                row[kind] = .failed
            }
        }
        exportProgressWorking[key] = row
        scheduleExportProgressFlush()
    }

    private func markFileFailed(file: String) {
        let key = URL(fileURLWithPath: file).standardizedFileURL
        var row = exportProgressWorking[key] ?? [:]
        for kind in ExportKind.allCases where row[kind] == .inProgress || row[kind] == .pending {
            row[kind] = .failed
        }
        exportProgressWorking[key] = row
        scheduleExportProgressFlush()
    }

    private func markInterruptedRunProgress() {
        var updated = exportProgressWorking
        for (file, states) in exportProgressWorking {
            var row = states
            for kind in ExportKind.allCases where row[kind] == .inProgress {
                row[kind] = .failed
            }
            updated[file] = row
        }
        exportProgressWorking = updated
        scheduleExportProgressFlush(immediate: true)
    }

    private func scheduleExportProgressFlush(immediate: Bool = false) {
        if immediate {
            exportProgressFlushWorkItem?.cancel()
            exportProgressFlushWorkItem = nil
            exportProgressByFile = exportProgressWorking
            return
        }

        guard exportProgressFlushWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.exportProgressFlushWorkItem = nil
            self.exportProgressByFile = self.exportProgressWorking
        }
        exportProgressFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.uiFlushInterval, execute: workItem)
    }

    private func persistOutputDirectory(_ directoryURL: URL) {
        UserDefaults.standard.set(directoryURL.path, forKey: Self.outputDirectoryDefaultsKey)
    }

    private static func initialOutputDirectoryURL() -> URL {
        if let persistedPath = UserDefaults.standard.string(forKey: outputDirectoryDefaultsKey), !persistedPath.isEmpty {
            return URL(fileURLWithPath: persistedPath, isDirectory: true)
        }
        return defaultOutputDirectoryURL()
    }

    private static func initialCompletionSoundChoiceID(choices: [CompletionSoundChoice]) -> String {
        if let persisted = UserDefaults.standard.string(forKey: completionSoundChoiceDefaultsKey),
           choices.contains(where: { $0.id == persisted }) {
            return persisted
        }
        if let tink = choices.first(where: { $0.title.caseInsensitiveCompare("Tink") == .orderedSame }) {
            return tink.id
        }
        if let glass = choices.first(where: { $0.title.caseInsensitiveCompare("Glass") == .orderedSame }) {
            return glass.id
        }
        return choices.first?.id ?? "system-beep"
    }

    private static func discoverCompletionSoundChoices() -> [CompletionSoundChoice] {
        var choices: [CompletionSoundChoice] = [
            CompletionSoundChoice(id: "system-beep", title: "System Beep", fileURL: nil)
        ]

        let fileManager = FileManager.default
        let directories: [URL] = [
            URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
            URL(fileURLWithPath: "/Library/Sounds", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds", isDirectory: true),
        ]
        let supportedExtensions = Set(["aiff", "wav", "caf", "mp3", "m4a"])
        var seenNames: Set<String> = []

        for directory in directories {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in urls {
                let ext = fileURL.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else {
                    continue
                }
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false else {
                    continue
                }

                let title = fileURL.deletingPathExtension().lastPathComponent
                let dedupeKey = title.lowercased()
                guard seenNames.insert(dedupeKey).inserted else {
                    continue
                }
                choices.append(CompletionSoundChoice(id: fileURL.path, title: title, fileURL: fileURL))
            }
        }

        let systemBeep = choices.removeFirst()
        choices.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        choices.insert(systemBeep, at: 0)
        return choices
    }

    private static func prepareAutosaveLogFile() -> LogAutosaveSetup {
        let fileManager = FileManager.default
        guard let autosaveDirectoryURL = autosaveLogDirectoryURL(fileManager: fileManager) else {
            return LogAutosaveSetup(
                directoryURL: nil,
                fileURL: nil,
                warningMessage: "Could not resolve ~/Library/Logs."
            )
        }

        do {
            try fileManager.createDirectory(at: autosaveDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return LogAutosaveSetup(
                directoryURL: autosaveDirectoryURL,
                fileURL: nil,
                warningMessage: error.localizedDescription
            )
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let suffix = String(UUID().uuidString.prefix(8))
        let filename = "session-\(timestamp)-\(suffix).log"
        let logFileURL = autosaveDirectoryURL.appendingPathComponent(filename, isDirectory: false)

        guard fileManager.createFile(atPath: logFileURL.path, contents: nil) else {
            return LogAutosaveSetup(
                directoryURL: autosaveDirectoryURL,
                fileURL: nil,
                warningMessage: "Could not create \(filename)."
            )
        }

        return LogAutosaveSetup(
            directoryURL: autosaveDirectoryURL,
            fileURL: logFileURL,
            warningMessage: nil
        )
    }

    private static func autosaveLogDirectoryURL(fileManager: FileManager) -> URL? {
        guard let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(autosaveLogDirectoryName, isDirectory: true)
    }

    private static func defaultOutputDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let picturesURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return picturesURL.appendingPathComponent("ProArchive Converter Exports", isDirectory: true)
    }

    private static func defaultBackendExecutableURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "procreate-to-tif-cli", withExtension: nil) {
            return bundled
        }
        if let bundledInBackend = Bundle.main.url(
            forResource: "procreate-to-tif-cli",
            withExtension: nil,
            subdirectory: "backend"
        ) {
            return bundledInBackend
        }

        if let envPath = ProcessInfo.processInfo.environment["PROARCHIVE_CLI_PATH"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        if let envPath = ProcessInfo.processInfo.environment["PROCREATE_CLI_PATH"], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }

        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        let candidates = [
            // Proximity to CWD (run from app dir)
            cwd.appendingPathComponent("backend-bundle/procreate-to-tif-cli"),
            cwd.appendingPathComponent("backend-bundle/dist/procreate-to-tif-cli/procreate-to-tif-cli"),

            // Proximity to CWD (run from repo root)
            cwd.appendingPathComponent("macos-app/ProArchiveConverter/backend-bundle/procreate-to-tif-cli"),
            cwd.appendingPathComponent("dist/procreate-to-tif-cli/procreate-to-tif-cli"),
            cwd.appendingPathComponent("dist/procreate-to-tif-cli"),

            // Proximity to CWD (run from packaging dir or similar)
            cwd.appendingPathComponent("../dist/procreate-to-tif-cli/procreate-to-tif-cli"),
            cwd.appendingPathComponent("../../dist/procreate-to-tif-cli/procreate-to-tif-cli"),
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        return nil
    }
}
