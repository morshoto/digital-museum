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
    private struct WindowedPresentation {
        let frame: NSRect
        let styleMask: NSWindow.StyleMask
        let collectionBehavior: NSWindow.CollectionBehavior
        let isMovable: Bool
        let applicationOptions: NSApplication.PresentationOptions
    }

    private var didEnterExhibition = false
    private var isExhibitionFullscreen = false
    private var windowedPresentation: WindowedPresentation?
    private var fullscreenRetry: DispatchWorkItem?
    private var windowObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowObservers.append(NotificationCenter.default.addObserver(forName: .toggleFullscreen, object: nil, queue: .main) { [weak self] _ in
            self?.toggleFullscreen()
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.enterExhibitionWhenWindowIsReady()
            })
        }
        // Exhibition mode is the default: the first window fills the display
        // without requiring a visitor or operator to touch the keyboard.
        enterExhibitionWhenWindowIsReady()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fullscreenRetry?.cancel()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    private func enterExhibitionWhenWindowIsReady() {
        guard !didEnterExhibition else { return }
        guard let window = Self.exhibitionWindow else {
            scheduleFullscreenRetry()
            return
        }
        fullscreenRetry?.cancel()
        fullscreenRetry = nil
        enterFullscreen(window)
        didEnterExhibition = true
    }

    private func toggleFullscreen() {
        guard let window = Self.exhibitionWindow else {
            didEnterExhibition = false
            scheduleFullscreenRetry()
            return
        }
        if isExhibitionFullscreen {
            exitFullscreen(window)
        } else {
            enterFullscreen(window)
        }
    }

    private func enterFullscreen(_ window: NSWindow) {
        guard !isExhibitionFullscreen, let screen = window.screen ?? NSScreen.main else { return }
        windowedPresentation = WindowedPresentation(
            frame: window.frame,
            styleMask: window.styleMask,
            collectionBehavior: window.collectionBehavior,
            isMovable: window.isMovable,
            applicationOptions: NSApp.presentationOptions
        )
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.styleMask = [.borderless]
        window.isMovable = false
        NSApp.presentationOptions.formUnion([.autoHideDock, .autoHideMenuBar])
        window.setFrame(screen.frame, display: true)
        isExhibitionFullscreen = true
        logDiagnostic("fullscreen_entered=1 width=\(Int(screen.frame.width)) height=\(Int(screen.frame.height))")
    }

    private func exitFullscreen(_ window: NSWindow) {
        guard isExhibitionFullscreen, let presentation = windowedPresentation else { return }
        NSApp.presentationOptions = presentation.applicationOptions
        window.styleMask = presentation.styleMask
        window.collectionBehavior = presentation.collectionBehavior
        window.isMovable = presentation.isMovable
        window.setFrame(presentation.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        isExhibitionFullscreen = false
        windowedPresentation = nil
        logDiagnostic("fullscreen_entered=0")
    }

    private func scheduleFullscreenRetry() {
        guard !didEnterExhibition else { return }
        if let fullscreenRetry, !fullscreenRetry.isCancelled { return }
        let retry = DispatchWorkItem { [weak self] in
            self?.fullscreenRetry = nil
            self?.logDiagnostic("fullscreen_retry=1")
            self?.enterExhibitionWhenWindowIsReady()
        }
        fullscreenRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: retry)
    }

    private func logDiagnostic(_ message: String) {
        guard ProcessInfo.processInfo.environment["EVOLVING_DIAGNOSTICS"] == "1" else { return }
        print("[installation] \(message)")
    }

    private static var exhibitionWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
    }
}
