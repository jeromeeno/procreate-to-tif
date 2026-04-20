import Foundation

public struct ConversionLogDecoder: Sendable {
    private let decoder: JSONDecoder

    public init() {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = jsonDecoder
    }

    public func decodeLine(_ rawLine: String) -> ConversionLogEvent {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .malformed(rawLine: rawLine)
        }
        guard let data = trimmed.data(using: .utf8) else {
            return .malformed(rawLine: rawLine)
        }
        guard let envelope = try? decoder.decode(EventEnvelope.self, from: data) else {
            return .malformed(rawLine: rawLine)
        }

        switch envelope.event {
        case "run_start":
            guard let payload = try? decoder.decode(RunStartPayload.self, from: data) else {
                return .malformed(rawLine: rawLine)
            }
            return .runStart(total: payload.total)

        case "file_start":
            guard let payload = try? decoder.decode(FileStartPayload.self, from: data) else {
                return .malformed(rawLine: rawLine)
            }
            return .fileStart(
                file: payload.file,
                index: payload.index,
                total: payload.total
            )

        case "file_output":
            guard let payload = try? decoder.decode(FileOutputPayload.self, from: data) else {
                return .malformed(rawLine: rawLine)
            }
            return .fileOutput(
                file: payload.file,
                index: payload.index,
                total: payload.total,
                output: payload.output,
                status: payload.status,
                path: payload.path,
                message: payload.message
            )

        case "file_success":
            guard let payload = try? decoder.decode(FileSuccessPayload.self, from: data) else {
                return .malformed(rawLine: rawLine)
            }
            return .fileSuccess(
                file: payload.file,
                index: payload.index,
                total: payload.total,
                width: payload.width,
                height: payload.height,
                layerCount: payload.layerCount,
                outputs: payload.outputs,
                skipped: payload.skipped ?? []
            )

        case "file_error":
            guard let payload = try? decoder.decode(FileErrorPayload.self, from: data) else {
                return .malformed(rawLine: rawLine)
            }
            return .fileError(
                file: payload.file,
                index: payload.index,
                total: payload.total,
                message: payload.message,
                errorCode: payload.errorCode
            )

        case "run_complete":
            guard let payload = try? decoder.decode(RunCompletePayload.self, from: data) else {
                return .malformed(rawLine: rawLine)
            }
            return .runComplete(
                total: payload.total,
                successes: payload.successes,
                failures: payload.failures
            )

        default:
            return .unknown(name: envelope.event, rawLine: rawLine)
        }
    }
}

private struct EventEnvelope: Decodable {
    let event: String
}

private struct RunStartPayload: Decodable {
    let total: Int
}

private struct FileStartPayload: Decodable {
    let file: String
    let index: Int
    let total: Int
}

private struct FileOutputPayload: Decodable {
    let file: String
    let index: Int
    let total: Int
    let output: String
    let status: String
    let path: String?
    let message: String?
}

private struct FileSuccessPayload: Decodable {
    let file: String
    let index: Int
    let total: Int
    let width: Int
    let height: Int
    let layerCount: Int
    let outputs: [String: String]
    let skipped: [String]?
}

private struct FileErrorPayload: Decodable {
    let file: String
    let index: Int
    let total: Int
    let message: String
    let errorCode: String
}

private struct RunCompletePayload: Decodable {
    let total: Int
    let successes: Int
    let failures: Int
}
