import SwiftUI

@main
struct HangarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.snippetManager)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)

        Window("Hangar", id: "main") {
            ContentView()
                .environment(appDelegate.snippetManager)
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Snippet") {
                    appDelegate.snippetManager.addSnippet()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let snippetManager = SnippetManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no dock icon, lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        // When the settings window closes, hide the app to return focus.
        // Launched terminals and apps are independent and outlive Hangar by
        // default; quitting only closes them when the user opts into
        // "close launched on quit" (see applicationShouldTerminate).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func handleWindowClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if NSApp.windows.filter({ $0.isVisible && $0.className != "NSStatusBarWindow" }).isEmpty {
                NSApp.hide(nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // No-op unless the user opted into "close launched on quit". Runs
        // synchronously so the windows/apps actually close before we exit.
        snippetManager.closeAllRunningSync()
        return .terminateNow
    }
}
