import Library
import Playback
import SwiftData
import SwiftUI

@main
struct EarReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var imports: ImportCoordinator
    @State private var player = PlayerController(engine: FakeEngine()) // M4 merge: swap for AVPlayerEngine()

    init() {
        do {
            container = try LibraryStore.makeContainer()
        } catch {
            fatalError("Couldn't open the library store: \(error)")
        }
        _imports = State(initialValue: ImportCoordinator(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(Theme.primary)
                .environment(imports)
                .environment(player)
                .onOpenURL { imports.open($0) }
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                imports.importSharedDocuments()
            }
        }
    }
}
