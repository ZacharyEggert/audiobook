import Library
import Playback
import SwiftUI

struct RootTabView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(PlayerController.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayerPresented = false
    @Namespace private var playerTransition

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeScreen()
            }
            Tab("Library", systemImage: "books.vertical") {
                LibraryScreen()
            }
            Tab("Stats", systemImage: "chart.bar") {
                StatsScreen()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen()
            }
            Tab(role: .search) {
                SearchScreen { isPlayerPresented = true }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .miniPlayer(isEnabled: player.book != nil) {
            MiniPlayerAccessory { isPlayerPresented = true }
                .matchedTransitionSource(id: "player", in: playerTransition)
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            if reduceMotion {
                FullPlayerScreen()
            } else {
                FullPlayerScreen().navigationTransition(.zoom(sourceID: "player", in: playerTransition))
            }
        }
        .sheet(isPresented: Binding { imports.results != nil } set: {
            if !$0 {
                imports.results = nil
            }
        }) {
            if let results = imports.results {
                ImportResultsSheet(summary: results)
            }
        }
        .alert("Import Failed", isPresented: Binding { imports.lastError != nil } set: { _ in imports.lastError = nil }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(imports.lastError ?? "")
        }
        .alert("Playback Failed", isPresented: Binding { player.lastError != nil } set: { _ in player.lastError = nil }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.lastError ?? "")
        }
    }
}

private extension View {
    /// The bottom accessory, removed when `isEnabled` is false.
    @ViewBuilder func miniPlayer(isEnabled: Bool, @ViewBuilder content: () -> some View) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled, content: content)
        } else if isEnabled {
            // ponytail: on 26.0 toggling rebuilds the TabView (tab selection resets); drop with a 26.1 deployment target
            tabViewBottomAccessory(content: content)
        } else {
            self
        }
    }
}

#Preview {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    RootTabView()
        .tint(Theme.primary)
        .environment(ImportCoordinator(container: container))
        .environment(PlayerController.preview())
        .modelContainer(container)
}
