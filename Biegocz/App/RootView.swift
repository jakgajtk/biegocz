import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Start", systemImage: "play.circle") {
                StartView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
            Tab("Exercises", systemImage: "dumbbell") {
                ExerciseLibraryView()
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
        .environment(AppDependencies.live())
}
