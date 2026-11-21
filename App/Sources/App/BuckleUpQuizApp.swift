import SwiftUI

@main
struct BuckleUpQuizApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.settings)
                .environment(environment.entitlements)
                .task { await environment.loadContent() }
        }
    }
}
