import SwiftData
import SwiftUI

@main
struct BiegoczApp: App {
    @State private var dependencies = AppDependencies.live()
    private let container: ModelContainer

    init() {
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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
        .modelContainer(container)
    }
}
