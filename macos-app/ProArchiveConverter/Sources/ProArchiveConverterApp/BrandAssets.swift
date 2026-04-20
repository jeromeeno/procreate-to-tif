import AppKit
import Foundation

enum BrandAssets {
    private static let resourceSubdirectories: [String?] = [
        "Resources/branding",
        "branding",
        nil,
    ]

    static let logoImage: NSImage? = loadLogoImage()
    static let appIconImage: NSImage? = loadAppIconImage()

    private static func loadLogoImage() -> NSImage? {
        if let svgURL = resourceURL(name: "stylusflame", ext: "svg"),
           let image = NSImage(contentsOf: svgURL) {
            return image
        }
        if let pngURL = resourceURL(name: "stylusflame", ext: "png"),
           let image = NSImage(contentsOf: pngURL) {
            return image
        }
        return nil
    }

    private static func loadAppIconImage() -> NSImage? {
        if let svgURL = resourceURL(name: "stylusflame", ext: "svg"),
           let image = NSImage(contentsOf: svgURL) {
            return preparedAppIconImage(from: image)
        }
        if let pngURL = resourceURL(name: "stylusflame", ext: "png"),
           let image = NSImage(contentsOf: pngURL) {
            return preparedAppIconImage(from: image)
        }
        if let logoImage {
            return preparedAppIconImage(from: logoImage)
        }
        return nil
    }

    private static func preparedAppIconImage(from image: NSImage) -> NSImage {
        let appIcon = image.copy() as? NSImage ?? image
        appIcon.isTemplate = false
        if appIcon.size.width < 512 || appIcon.size.height < 512 {
            appIcon.size = NSSize(width: 512, height: 512)
        }
        return appIcon
    }

    private static func resourceURL(name: String, ext: String) -> URL? {
        for subdirectory in resourceSubdirectories {
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }
        return nil
    }
}
