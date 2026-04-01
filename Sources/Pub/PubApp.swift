import AppKit
import SwiftUI

@main
struct PubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Pub") {
            ContentView(model: model)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Packages") {
                    model.refreshFromCommand()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isRefreshing || model.isRunningOperation)

                Button("Upgrade All Outdated Packages") {
                    model.upgradeAllFromCommand()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.isRefreshing || model.isRunningOperation || model.outdatedPackages.isEmpty)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
