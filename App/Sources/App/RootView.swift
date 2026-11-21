import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            switch environment.content {
            case .loading:
                ProgressView("Loading questions…")
                    .font(Theme.body)
            case .failed(let message):
                ContentUnavailableView("Couldn't load questions", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .loaded(let bank):
                HomeView(bank: bank)
            }
        }
        .tint(Theme.accent)
    }
}
