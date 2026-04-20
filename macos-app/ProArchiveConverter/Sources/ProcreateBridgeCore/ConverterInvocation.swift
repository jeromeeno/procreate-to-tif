import Foundation

public struct ConverterInvocation: Sendable, Equatable {
    public var executableURL: URL
    public var inputFiles: [URL]
    public var outputDirectoryURL: URL
    public var options: ConversionOptions

    public init(
        executableURL: URL,
        inputFiles: [URL],
        outputDirectoryURL: URL,
        options: ConversionOptions = ConversionOptions()
    ) {
        self.executableURL = executableURL
        self.inputFiles = inputFiles
        self.outputDirectoryURL = outputDirectoryURL
        self.options = options
    }

    public var arguments: [String] {
        var args: [String] = [
            "--outdir",
            outputDirectoryURL.path,
        ]

        if !options.writePSD {
            args.append("--no-psd")
        }
        if options.writeFlatPNG {
            args.append("--flat-png")
        }
        if options.writeFlatJPG {
            args.append("--flat-jpg")
        }
        if options.writeAnimatedWebP {
            args.append("--animated-webp")
        }
        if options.writeAnimatedGIF {
            args.append("--animated-gif")
        }
        if options.writeTimelapseMP4 {
            args.append("--timelapse-mp4")
        }
        if options.applyMask {
            args.append("--apply-mask")
        }
        if !options.includeBackground {
            args.append("--no-background")
        }
        if !options.unpremultiply {
            args.append("--no-unpremultiply")
        }

        args.append(contentsOf: [
            "--jpg-quality",
            String(options.normalizedJPGQuality),
            "--log-format",
            options.logFormat.rawValue,
        ])
        if options.existingOutputBehavior != .overwrite {
            args.append(contentsOf: ["--if-exists", options.existingOutputBehavior.rawValue])
        }

        args.append(contentsOf: inputFiles.map(\.path))
        return args
    }
}
