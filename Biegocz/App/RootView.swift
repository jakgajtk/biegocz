import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case start, history, exercises, settings
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionCoordinator.self) private var coordinator
    @AppStorage(AppSettings.appearanceKey) private var appearance = AppAppearance.system
    @State private var tab = AppTab.start
    #if DEBUG
    @State private var debugDestination: DebugDestination?
    #endif

    var body: some View {
        TabView(selection: $tab) {
            Tab("Start", systemImage: "play.circle", value: .start) {
                StartView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView()
            }
            Tab("Exercises", systemImage: "dumbbell", value: .exercises) {
                ExerciseLibraryView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(appearance.colorScheme)
        .fullScreenCover(isPresented: Binding(
            get: { coordinator.hasActiveSession },
            set: { _ in }
        )) {
            Group {
                if let model = coordinator.gymSession {
                    GymSessionView(model: model, onClose: coordinator.closeGym)
                } else {
                    CardioFlowView()
                }
            }
            .fontDesign(.rounded)
            .preferredColorScheme(appearance.colorScheme)
        }
        .task {
            #if DEBUG
            if DebugLaunch.screen != nil {
                openDebugScreen()
                return
            }
            #endif
            coordinator.findRecoverable(in: modelContext)
        }
        .alert(
            recoveryTitle,
            isPresented: Binding(
                get: { coordinator.recoverable != nil },
                set: { _ in }
            ),
            presenting: coordinator.recoverable
        ) { _ in
            Button("Resume") { coordinator.resumeRecoverable(in: modelContext) }
            Button("Save") { coordinator.saveRecoverable(in: modelContext) }
            Button("Discard", role: .destructive) { coordinator.discardRecoverable(in: modelContext) }
        } message: { activity in
            Text("Started \(Formatters.dateTime(activity.startDate)).")
        }
        #if DEBUG
        .sheet(item: $debugDestination) { destination in
            NavigationStack {
                switch destination {
                case .exercise(let exercise): ExerciseDetailView(exercise: exercise)
                case .activity(let activity): ActivityDetailView(activity: activity)
                }
            }
        }
        #endif
    }

    private var recoveryTitle: Text {
        switch coordinator.recoverable?.type {
        case .run: Text("Unfinished run")
        case .ride: Text("Unfinished ride")
        case .gym, nil: Text("Unfinished workout")
        }
    }
}

#if DEBUG
private enum DebugDestination: Identifiable {
    case exercise(Exercise)
    case activity(Activity)

    var id: String {
        switch self {
        case .exercise(let exercise): "exercise-\(exercise.id)"
        case .activity(let activity): "activity-\(activity.id)"
        }
    }
}

extension RootView {
    private func openDebugScreen() {
        guard let screen = DebugLaunch.screen else { return }
        switch screen {
        case .history:
            tab = .history
        case .exercises:
            tab = .exercises
        case .settings:
            tab = .settings
        case .gym, .picker, .summary:
            coordinator.startGym(in: modelContext)
            guard let model = coordinator.gymSession else { return }
            model.addExercise(DemoData.exercise("bench_press", in: modelContext))
            model.addExercise(DemoData.exercise("pull_up", in: modelContext))
            let bench = model.entries[0]
            model.addSet(to: bench)
            model.toggleDone(bench.sortedSets[0])
            if screen == .summary {
                model.finish(now: model.activity.startDate.addingTimeInterval(3_725))
            }
        case .exerciseDetail:
            debugDestination = .exercise(DemoData.exercise("bench_press", in: modelContext))
        case .activityDetail:
            let latest = try? modelContext.fetch(FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])).first
            if let latest { debugDestination = .activity(latest) }
        case .prestart:
            coordinator.prepareCardio(.run)
        case .run, .ride:
            coordinator.prepareCardio(screen == .run ? .run : .ride)
            coordinator.startCardio(in: modelContext)
        }
    }
}
#endif

#Preview {
    RootView()
        .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
        .environment(AppDependencies.live())
        .environment(SessionCoordinator(
            restNotifier: NoOpRestNotifier(), location: GPXReplayLocationProvider(), health: NoOpHealthStore()
        ))
}
