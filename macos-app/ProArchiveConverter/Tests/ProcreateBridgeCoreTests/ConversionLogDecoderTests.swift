import Testing
@testable import ProcreateBridgeCore

@Test
func conversionLogDecoderDecodesKnownEvents() {
    let decoder = ConversionLogDecoder()

    let runStart = decoder.decodeLine(#"{"event":"run_start","total":2}"#)
    #expect(runStart == .runStart(total: 2))

    let fileStart = decoder.decodeLine(#"{"event":"file_start","file":"/tmp/a.procreate","index":1,"total":2}"#)
    #expect(fileStart == .fileStart(file: "/tmp/a.procreate", index: 1, total: 2))

    let fileOutput = decoder.decodeLine(#"{"event":"file_output","file":"/tmp/a.procreate","index":1,"total":2,"output":"psd","status":"completed","path":"/tmp/a.psd"}"#)
    #expect(
        fileOutput == .fileOutput(
            file: "/tmp/a.procreate",
            index: 1,
            total: 2,
            output: "psd",
            status: "completed",
            path: "/tmp/a.psd",
            message: nil
        )
    )

    let fileSuccess = decoder.decodeLine(#"{"event":"file_success","file":"/tmp/a.procreate","index":1,"total":2,"width":100,"height":200,"layer_count":4,"outputs":{"psd":"/tmp/a.psd"},"skipped":["gif"]}"#)
    #expect(
        fileSuccess == .fileSuccess(
            file: "/tmp/a.procreate",
            index: 1,
            total: 2,
            width: 100,
            height: 200,
            layerCount: 4,
            outputs: ["psd": "/tmp/a.psd"],
            skipped: ["gif"]
        )
    )

    let fileError = decoder.decodeLine(#"{"event":"file_error","file":"/tmp/a.procreate","index":2,"total":2,"message":"Missing file","error_code":"missing_input"}"#)
    #expect(
        fileError == .fileError(
            file: "/tmp/a.procreate",
            index: 2,
            total: 2,
            message: "Missing file",
            errorCode: "missing_input"
        )
    )

    let runComplete = decoder.decodeLine(#"{"event":"run_complete","total":2,"successes":1,"failures":1}"#)
    #expect(runComplete == .runComplete(total: 2, successes: 1, failures: 1))
}

@Test
func conversionLogDecoderHandlesUnknownAndMalformed() {
    let decoder = ConversionLogDecoder()

    let unknown = decoder.decodeLine(#"{"event":"future_event","x":1}"#)
    #expect(unknown == .unknown(name: "future_event", rawLine: #"{"event":"future_event","x":1}"#))

    let malformed = decoder.decodeLine("not-json")
    #expect(malformed == .malformed(rawLine: "not-json"))
}
