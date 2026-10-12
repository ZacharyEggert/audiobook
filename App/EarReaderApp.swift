import SwiftUI

@main
struct EarReaderApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(Theme.primary)
        }
    }
}
