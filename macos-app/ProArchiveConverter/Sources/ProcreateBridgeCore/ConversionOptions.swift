import Foundation

public enum ConversionLogFormat: String, Sendable, CaseIterable {
    case text
    case jsonl
}

public enum ExistingOutputBehavior: String, Sendable, CaseIterable {
    case overwrite
    case skip
}

public struct ConversionOptions: Sendable, Equatable {
    public var writePSD: Bool
    public var writeFlatPNG: Bool
    public var writeFlatJPG: Bool
    public var writeAnimatedWebP: Bool
    public var writeAnimatedGIF: Bool
    public var writeTimelapseMP4: Bool
    public var applyMask: Bool
    public var includeBackground: Bool
    public var unpremultiply: Bool
    public var jpgQuality: Int
    public var logFormat: ConversionLogFormat
    public var existingOutputBehavior: ExistingOutputBehavior

    public init(
        writePSD: Bool = true,
        writeFlatPNG: Bool = true,
        writeFlatJPG: Bool = true,
        writeAnimatedWebP: Bool = true,
        writeAnimatedGIF: Bool = true,
        writeTimelapseMP4: Bool = true,
        applyMask: Bool = false,
        includeBackground: Bool = true,
        unpremultiply: Bool = true,
        jpgQuality: Int = 95,
        logFormat: ConversionLogFormat = .jsonl,
        existingOutputBehavior: ExistingOutputBehavior = .overwrite
    ) {
        self.writePSD = writePSD
        self.writeFlatPNG = writeFlatPNG
        self.writeFlatJPG = writeFlatJPG
        self.writeAnimatedWebP = writeAnimatedWebP
        self.writeAnimatedGIF = writeAnimatedGIF
        self.writeTimelapseMP4 = writeTimelapseMP4
        self.applyMask = applyMask
        self.includeBackground = includeBackground
        self.unpremultiply = unpremultiply
        self.jpgQuality = jpgQuality
        self.logFormat = logFormat
        self.existingOutputBehavior = existingOutputBehavior
    }

    public var normalizedJPGQuality: Int {
        max(1, min(100, jpgQuality))
    }
}
