import SwiftUI

struct RootTabView: View {
    @State private var searchText = ""

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                PlaceholderScreen(title: "Home", systemImage: "house")
            }
            Tab("Library", systemImage: "books.vertical") {
                PlaceholderScreen(title: "Library", systemImage: "books.vertical")
            }
            Tab("Stats", systemImage: "chart.bar") {
                PlaceholderScreen(title: "Stats", systemImage: "chart.bar")
            }
            Tab("Settings", systemImage: "gearshape") {
                PlaceholderScreen(title: "Settings", systemImage: "gearshape")
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
    RootTabView().tint(Theme.primary)
}
