import Library
import SwiftUI

struct RootTabView: View {
    @Environment(ImportCoordinator.self) private var imports
    @State private var searchText = ""

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                PlaceholderScreen(title: "Home", systemImage: "house")
            }
            Tab("Library", systemImage: "books.vertical") {
                LibraryScreen()
            }
            Tab("Stats", systemImage: "chart.bar") {
                PlaceholderScreen(title: "Stats", systemImage: "chart.bar")
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen()
            }
            Tab(role: .search) {
                NavigationStack {
                    ContentUnavailableView.search(text: searchText)
                        .navigationTitle("Search")
                }
                .searchable(text: $searchText)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MiniPlayerPlaceholder()
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
    }
}

/// Scrollable stand-in so the tab bar minimize behavior can be seen.
private struct PlaceholderScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ScrollView {
                ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming soon"))
                    .padding(.vertical, 120)
                Color.clear.frame(height: 800)
            }
            .background(Theme.background)
            .navigationTitle(title)
        }
    }
}

private struct MiniPlayerPlaceholder: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.surfaceSecondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading) {
                Text("Nothing playing").font(.subheadline.bold())
                if placement != .inline {
                    Text("Import a book to start").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "play.fill")
                .accessibilityLabel("Play")
        }
        .padding(.horizontal)
    }
}

#Preview {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    RootTabView()
        .tint(Theme.primary)
        .environment(ImportCoordinator(container: container))
        .modelContainer(container)
}
