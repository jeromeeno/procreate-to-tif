import Foundation
import Testing
@testable import ProcreateBridgeCore

@Test
func converterProcessRunnerStreamsJsonlEvents() throws {
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("procreate-runner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let scriptURL = temporaryRoot.appendingPathComponent("fake-cli.sh")
    let script = """
    #!/bin/sh
    echo '{"event":"run_start","total":1}'
    echo '{"event":"file_start","file":"sample.procreate","index":1,"total":1}'
    echo '{"event":"file_success","file":"sample.procreate","index":1,"total":1,"width":100,"height":200,"layer_count":3,"outputs":{"psd":"sample.psd"}}'
    echo '{"event":"run_complete","total":1,"successes":1,"failures":0}'
    """
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let sampleInput = temporaryRoot.appendingPathComponent("sample.procreate")
    try Data().write(to: sampleInput)

    let invocation = ConverterInvocation(
        executableURL: scriptURL,
        inputFiles: [sampleInput],
        outputDirectoryURL: temporaryRoot.appendingPathComponent("exports", isDirectory: true),
        options: ConversionOptions(logFormat: .jsonl)
    )

    let collector = EventCollector()
    let runner = ConverterProcessRunner()
    let result = try runner.run(invocation: invocation) { event in
        collector.append(event)
    }
    let events = collector.snapshot()

    #expect(result.exitCode == 0)
    #expect(result.stderr.isEmpty)
    #expect(events.count == 4)
    #expect(events[0] == .runStart(total: 1))
    #expect(events[1] == .fileStart(file: "sample.procreate", index: 1, total: 1))
    #expect(
        events[2] == .fileSuccess(
            file: "sample.procreate",
            index: 1,
            total: 1,
            width: 100,
            height: 200,
            layerCount: 3,
            outputs: ["psd": "sample.psd"],
            skipped: []
        )
    )
    #expect(events[3] == .runComplete(total: 1, successes: 1, failures: 0))
}

private final class EventCollector: @unchecked Sendable {
    private var events: [ConversionLogEvent] = []
    private let lock = NSLock()

    func append(_ event: ConversionLogEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func snapshot() -> [ConversionLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
