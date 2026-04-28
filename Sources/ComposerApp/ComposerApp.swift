import SwiftUI

@main
struct ComposerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    await model.load()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Task") {
                Button("New Task") {
                    Task {
                        await model.createTask()
                    }
                }
                .keyboardShortcut("n")
            }
        }
    }
}
