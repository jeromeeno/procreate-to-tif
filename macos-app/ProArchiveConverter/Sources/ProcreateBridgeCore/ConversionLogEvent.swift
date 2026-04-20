import Foundation

public enum ConversionLogEvent: Sendable, Equatable {
    case runStart(total: Int)
    case fileStart(file: String, index: Int, total: Int)
    case fileOutput(file: String, index: Int, total: Int, output: String, status: String, path: String?, message: String?)
    case fileSuccess(
        file: String,
        index: Int,
        total: Int,
        width: Int,
        height: Int,
        layerCount: Int,
        outputs: [String: String],
        skipped: [String]
    )
    case fileError(file: String, index: Int, total: Int, message: String, errorCode: String)
    case runComplete(total: Int, successes: Int, failures: Int)
    case unknown(name: String, rawLine: String)
    case malformed(rawLine: String)
}

public extension ConversionLogEvent {
    var summary: String {
        switch self {
        case let .runStart(total):
            return "Run started (\(total) file(s))."
        case let .fileStart(file, index, total):
            return "Starting \(index)/\(total): \(URL(fileURLWithPath: file).lastPathComponent)"
        case let .fileOutput(file, index, total, output, status, _, message):
            let basename = URL(fileURLWithPath: file).lastPathComponent
            let suffix = message.map { " (\($0))" } ?? ""
            return "Output \(index)/\(total): \(basename) \(output.uppercased()) \(status)\(suffix)"
        case let .fileSuccess(file, index, total, width, height, layerCount, outputs, skipped):
            let basename = URL(fileURLWithPath: file).lastPathComponent
            let exported = outputs.keys.sorted().joined(separator: ", ")
            let skipText = skipped.isEmpty ? "" : " | skipped: \(skipped.joined(separator: ", "))"
            return "Finished \(index)/\(total): \(basename) (\(width)x\(height), \(layerCount) layers) | outputs: \(exported)\(skipText)"
        case let .fileError(file, index, total, message, errorCode):
            let basename = URL(fileURLWithPath: file).lastPathComponent
            return "Error \(index)/\(total): \(basename) [\(errorCode)] \(message)"
        case let .runComplete(total, successes, failures):
            return "Run complete: \(successes) success / \(failures) failure / \(total) total."
        case let .unknown(name, _):
            return "Unknown event: \(name)"
        case let .malformed(rawLine):
            return "Malformed line: \(rawLine)"
        }
    }
}
