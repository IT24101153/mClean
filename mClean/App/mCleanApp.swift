import SwiftUI

@main
struct mCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        Window("mClean", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 880, minHeight: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Screen.allCases) { screen in
                    Button(screen.title) { state.screen = screen }
                        .keyboardShortcut(screen.shortcut, modifiers: .command)
                }
            }
        }

        MenuBarExtra("mClean", systemImage: "leaf", isInserted: $showMenuBarExtra) {
            MenuBarPanel()
                .environment(state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
