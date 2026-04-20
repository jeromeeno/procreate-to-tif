import Foundation
import Testing
@testable import ProcreateBridgeCore

@Test
func converterInvocationBuildsArgumentsForEnabledOptions() {
    let options = ConversionOptions(
        writePSD: false,
        writeFlatPNG: true,
        writeFlatJPG: true,
        writeAnimatedWebP: true,
        writeAnimatedGIF: true,
        writeTimelapseMP4: true,
        applyMask: true,
        includeBackground: false,
        unpremultiply: false,
        jpgQuality: 123,
        logFormat: .jsonl,
        existingOutputBehavior: .skip
    )

    let invocation = ConverterInvocation(
        executableURL: URL(fileURLWithPath: "/tmp/procreate-cli"),
        inputFiles: [
            URL(fileURLWithPath: "/tmp/a.procreate"),
            URL(fileURLWithPath: "/tmp/b.procreate"),
        ],
        outputDirectoryURL: URL(fileURLWithPath: "/tmp/exports"),
        options: options
    )

    #expect(
        invocation.arguments == [
            "--outdir", "/tmp/exports",
            "--no-psd",
            "--flat-png",
            "--flat-jpg",
            "--animated-webp",
            "--animated-gif",
            "--timelapse-mp4",
            "--apply-mask",
            "--no-background",
            "--no-unpremultiply",
            "--jpg-quality", "100",
            "--log-format", "jsonl",
            "--if-exists", "skip",
            "/tmp/a.procreate",
            "/tmp/b.procreate",
        ]
    )
}
