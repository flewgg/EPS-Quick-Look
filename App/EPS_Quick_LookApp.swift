import AppKit
import SwiftUI

enum ManagedWindow: String {
    case settings
    case acknowledgements

    var id: String {
        rawValue
    }

    init?(_ identifier: NSUserInterfaceItemIdentifier?) {
        guard let identifier else {
            return nil
        }
        self.init(rawValue: identifier.rawValue)
    }
}

@MainActor
private enum DockVisibilityController {
    static var hasVisibleManagedWindow: Bool {
        NSApp.windows.contains { window in
            guard ManagedWindow(window.identifier) != nil else { return false }
            return window.isVisible && !window.isMiniaturized
        }
    }

    static func ensureRegularPolicy() {
        guard NSApp.activationPolicy() != .regular else { return }
        _ = NSApp.setActivationPolicy(.regular)
    }

    static func hideDockIfNoManagedWindows() {
        DispatchQueue.main.async {
            if !hasVisibleManagedWindow {
                _ = NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    var openSettingsWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.openSettingsWindow?()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow?()
        }
        return true
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard manages(notification) else {
            return
        }
        DockVisibilityController.ensureRegularPolicy()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard manages(notification) else {
            return
        }
        DockVisibilityController.hideDockIfNoManagedWindows()
    }

    private func manages(_ notification: Notification) -> Bool {
        guard let window = notification.object as? NSWindow else {
            return false
        }
        return ManagedWindow(window.identifier) != nil
    }
}

private struct OpenSettingsWindowInstaller: View {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .task {
                appDelegate.openSettingsWindow = {
                    DockVisibilityController.ensureRegularPolicy()
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: ManagedWindow.settings.id)
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
    }
}

@main
struct EPS_Quick_LookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var updaterController = AppUpdaterController()

    init() {
        PreviewTemporaryStorage.registerDefaults()
    }

    var body: some Scene {
        Window(Bundle.main.appName, id: ManagedWindow.settings.id) {
            SettingsView(updaterController: updaterController)
                .background(OpenSettingsWindowInstaller(appDelegate: appDelegate))
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)
            }

            CommandGroup(replacing: .help) {
                Button("Release Notes") {
                    NSWorkspace.shared.open(AppLink.releaseNotes.url)
                }

                Divider()

                Button("Privacy Policy") {
                    NSWorkspace.shared.open(AppLink.privacy.url)
                }

                Button("Contact Us") {
                    NSWorkspace.shared.open(AppLink.contact.url)
                }

                Divider()

                Button("Acknowledgements") {
                    openWindow(id: ManagedWindow.acknowledgements.id)
                }
            }
        }

        Window("Acknowledgements", id: ManagedWindow.acknowledgements.id) {
            AcknowledgementsWindowView()
                .frame(width: 720, height: 640)
        }
        .windowResizability(.contentSize)
    }
}
