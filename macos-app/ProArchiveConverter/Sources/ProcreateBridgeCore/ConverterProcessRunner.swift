import Foundation

public struct ConversionRunResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stderr: String
    public let terminatedBySignal: Bool

    public init(exitCode: Int32, stderr: String, terminatedBySignal: Bool = false) {
        self.exitCode = exitCode
        self.stderr = stderr
        self.terminatedBySignal = terminatedBySignal
    }
}

public enum ConverterProcessRunnerError: Error {
    case missingExecutable(String)
    case launchFailed(String)
}

public final class ConverterProcessRunner: @unchecked Sendable {
    private let logDecoder: ConversionLogDecoder
    private let processLock = NSLock()
    private var activeProcess: Process?

    public init(logDecoder: ConversionLogDecoder = ConversionLogDecoder()) {
        self.logDecoder = logDecoder
    }

    public func terminateCurrentProcess() {
        processLock.lock()
        defer { processLock.unlock() }
        activeProcess?.terminate()
    }

    @discardableResult
    public func run(
        invocation: ConverterInvocation,
        onEvent: @escaping @Sendable (ConversionLogEvent) -> Void
    ) throws -> ConversionRunResult {
        let executablePath = invocation.executableURL.path
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw ConverterProcessRunnerError.missingExecutable(executablePath)
        }

        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let syncQueue = DispatchQueue(label: "procreate.bridge.runner.sync")
        let readGroup = DispatchGroup()
        let stdoutAccumulator = LineAccumulator()
        let stderrAccumulator = LineAccumulator()
        let stderrBuffer = StringLineBuffer()

        readGroup.enter()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                syncQueue.sync {
                    for line in stdoutAccumulator.flush() {
                        onEvent(self.logDecoder.decodeLine(line))
                    }
                }
                readGroup.leave()
                return
            }

            syncQueue.sync {
                for line in stdoutAccumulator.append(data) {
                    onEvent(self.logDecoder.decodeLine(line))
                }
            }
        }

        readGroup.enter()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                syncQueue.sync {
                    stderrBuffer.append(contentsOf: stderrAccumulator.flush())
                }
                readGroup.leave()
                return
            }

            syncQueue.sync {
                stderrBuffer.append(contentsOf: stderrAccumulator.append(data))
            }
        }

        do {
            try process.run()
            processLock.lock()
            activeProcess = process
            processLock.unlock()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw ConverterProcessRunnerError.launchFailed(error.localizedDescription)
        }
        defer {
            processLock.lock()
            activeProcess = nil
            processLock.unlock()
        }

        process.waitUntilExit()
        readGroup.wait()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        return ConversionRunResult(
            exitCode: process.terminationStatus,
            stderr: stderrBuffer.joined(),
            terminatedBySignal: process.terminationReason == .uncaughtSignal
        )
    }
}

private final class LineAccumulator: @unchecked Sendable {
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        guard !data.isEmpty else {
            return []
        }
        buffer.append(data)
        return drainCompleteLines()
    }

    func flush() -> [String] {
        var lines = drainCompleteLines()
        if !buffer.isEmpty {
            lines.append(Self.decodeLineData(buffer))
            buffer.removeAll(keepingCapacity: false)
        }
        return lines
    }

    private func drainCompleteLines() -> [String] {
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[..<newlineIndex]
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            lines.append(Self.decodeLineData(Data(lineData)))
            buffer.removeSubrange(...newlineIndex)
        }
        return lines
    }

    private static func decodeLineData(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

private final class StringLineBuffer: @unchecked Sendable {
    private var lines: [String] = []

    func append(contentsOf newLines: [String]) {
        lines.append(contentsOf: newLines)
    }

    func joined() -> String {
        lines.joined(separator: "\n")
    }
}
