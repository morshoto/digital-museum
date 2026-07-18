import AppKit
import SwiftUI

@main
struct EvolvingImpressionistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = InstallationController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Toggle Developer Mode") { NotificationCenter.default.post(name: .toggleDeveloperMode, object: nil) }.keyboardShortcut("d")
                Button("Toggle Fullscreen") { NotificationCenter.default.post(name: .toggleFullscreen, object: nil) }.keyboardShortcut("f")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: .toggleFullscreen, object: nil, queue: .main) { _ in
            NSApp.windows.first?.toggleFullScreen(nil)
        }
        // Exhibition mode is the default: the first window fills the display
        // without requiring a visitor or operator to touch the keyboard.
        DispatchQueue.main.async {
            NSApp.windows.first?.toggleFullScreen(nil)
        }
    }
}
