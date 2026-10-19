import SwiftData
import SwiftUI

@main
struct BiegoczApp: App {
    @State private var dependencies: AppDependencies
    @State private var coordinator: SessionCoordinator
    private let container: ModelContainer

    init() {
        let dependencies = AppDependencies.live()
        _dependencies = State(initialValue: dependencies)
        _coordinator = State(initialValue: SessionCoordinator(
            restNotifier: Self.makeRestNotifier(),
            location: dependencies.location,
            health: dependencies.health,
            altitude: dependencies.altitude
        ))

        #if DEBUG
        if DebugLaunch.usesDemoData {
            container = DebugLaunch.makeDemoContainer()
            return
        }
        #endif
        do {
            container = try PersistenceController.makeContainer()
        } catch {
            // Never wipe the store to recover: a failed migration must not cost training history.
            fatalError("Could not open the data store: \(error)")
        }
        do {
            try ExerciseSeeder.seedIfNeeded(in: container.mainContext)
        } catch {
            assertionFailure("Seeding exercises failed: \(error)")
        }
    }

    private static func makeRestNotifier() -> RestNotifying {
        #if DEBUG
        // Demo screenshots shouldn't be covered by the permission prompt.
        if DebugLaunch.usesDemoData { return NoOpRestNotifier() }
        #endif
        return RestNotifier()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(coordinator)
        }
        .modelContainer(container)
    }
}
