import AppKit
import SwiftUI

private enum AppWindowID {
    static let about = "about-window"
}

final class ProArchiveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = BrandAssets.appIconImage {
            NSApp.applicationIconImage = appIcon
        }
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct ProArchiveConverterApp: App {
    @NSApplicationDelegateAdaptor(ProArchiveAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("ProArchive Converter") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1080, minHeight: 720)
        }

        Window("About ProArchive Converter", id: AppWindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)

        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ProArchive Converter") {
                    openWindow(id: AppWindowID.about)
                }
            }
        }
    }
}
