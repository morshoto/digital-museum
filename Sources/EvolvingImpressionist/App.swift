import AppKit
import EvolvingImpressionistCore
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
    private var didEnterExhibition = false
    private var fullscreenRetry: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: .toggleFullscreen, object: nil, queue: .main) { _ in
            Self.exhibitionWindow?.toggleFullScreen(nil)
        }
        // Exhibition mode is the default: the first window fills the display
        // without requiring a visitor or operator to touch the keyboard.
        enterExhibitionWhenWindowIsReady()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fullscreenRetry?.cancel()
    }

    private func enterExhibitionWhenWindowIsReady(attempt: Int = 0) {
        guard !didEnterExhibition else { return }
        guard let window = Self.exhibitionWindow else {
            guard attempt < 100 else { return }
            let retry = DispatchWorkItem { [weak self] in
                self?.enterExhibitionWhenWindowIsReady(attempt: attempt + 1)
            }
            fullscreenRetry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: retry)
            return
        }
        didEnterExhibition = true
        fullscreenRetry?.cancel()
        if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    private static var exhibitionWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
    }
}
