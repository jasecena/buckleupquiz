import SwiftUI

@main
struct BuckleUpQuizApp: App {
    @State private var environment = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.settings)
                .environment(environment.entitlements)
                .environment(environment.players)
                .environment(environment.telemetry)
                .environment(environment.allowance)
                .environment(environment.store)
                .task {
                    await environment.entitlements.detectTestBuild()
                    await environment.loadContent()
                    await environment.store.start()
                    await environment.telemetry.flush()
                    await environment.updateContent()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Queued error reports go out when the app is put away (ADR-0020).
            if phase == .background { Task { await environment.telemetry.flush() } }
            if phase == .active {
                environment.refreshAllowance()
                Task { await environment.updateContent() }
            }
        }
    }
}
