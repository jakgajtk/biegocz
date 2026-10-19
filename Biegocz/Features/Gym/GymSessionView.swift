import SwiftData
import SwiftUI

struct GymSessionView: View {
    @Bindable var model: GymSessionModel
    let onClose: () -> Void

    @State private var isPickingExercise = false
    @State private var isReordering = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false
    @FocusState private var focusedField: SetField?

    var body: some View {
        NavigationStack {
            if let summary = model.summary {
                WorkoutSummaryView(summary: summary, onDone: onClose)
            } else {
                sessionList
            }
        }
    }

    private var sessionList: some View {
        List {
            ForEach(model.entries) { entry in
                ExerciseSection(model: model, entry: entry, focusedField: $focusedField)
            }

            Section {
                Button {
                    isPickingExercise = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }

            Section("Note") {
                TextField("Add a note", text: Bindable(model.activity).note, axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit { model.save() }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ElapsedTimeView(start: model.activity.startDate)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Reorder exercises", systemImage: "arrow.up.arrow.down") {
                        isReordering = true
                    }
                    .disabled(model.entries.count < 2)
                    Button("Discard workout", systemImage: "trash", role: .destructive) {
                        isConfirmingDiscard = true
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") {
                    focusedField = nil
                    isConfirmingFinish = true
                }
                .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.restTimer != nil {
                RestTimerBar(model: model)
            }
        }
        #if DEBUG
        .onAppear {
            if DebugLaunch.screen == .picker { isPickingExercise = true }
        }
        #endif
        .sheet(isPresented: $isPickingExercise) {
            ExercisePickerView { exercise in
                model.addExercise(exercise)
            }
        }
        .sheet(isPresented: $isReordering) {
            ReorderExercisesView(model: model)
        }
        .confirmationDialog(
            "Finish workout?",
            isPresented: $isConfirmingFinish,
            titleVisibility: .visible
        ) {
            Button("Finish workout") { model.finish() }
                .disabled(!model.hasCompletedSets)
            Button("Cancel", role: .cancel) {}
        } message: {
            if !model.hasCompletedSets {
                Text("Mark at least one set as done to finish.")
            } else if model.hasUnfinishedSets {
                Text("Sets not marked as done will be removed.")
            }
        }
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard workout", role: .destructive) {
                model.discard()
                onClose()
            }
        } message: {
            Text("Everything logged in this workout will be deleted.")
        }
    }
}

/// Elapsed time since `start`, ticking every second.
struct ElapsedTimeView: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(verbatim: Formatters.duration(seconds: context.date.timeIntervalSince(start)))
                .font(.headline)
                .monospacedDigit()
        }
        .accessibilityLabel(Text("Elapsed time"))
    }
}

private struct ExerciseSection: View {
    let model: GymSessionModel
    let entry: WorkoutExercise
    var focusedField: FocusState<SetField?>.Binding

    @State private var isConfirmingRemoval = false

    private var loggingType: LoggingType { entry.exercise?.loggingType ?? .weightReps }

    var body: some View {
        Section {
            ForEach(Array(entry.sortedSets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    number: index + 1,
                    set: set,
                    loggingType: loggingType,
                    focusedField: focusedField,
                    onToggleDone: { model.toggleDone(set) },
                    onChange: { model.save() }
                )
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        model.removeSet(set, from: entry)
                    }
                }
            }

            Button {
                model.addSet(to: entry)
            } label: {
                Label("Add set", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: entry.exercise?.displayName ?? "")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    Spacer()
                    Menu("Exercise options", systemImage: "ellipsis") {
                        Button("Remove exercise", systemImage: "trash", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                }
                if let lastTime = model.lastTime(for: entry) {
                    Text(verbatim: LastTimeFormatting.text(for: lastTime, loggingType: loggingType))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .confirmationDialog(
            "Remove this exercise and its sets?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove exercise", role: .destructive) {
                model.removeExercise(entry)
            }
        }
    }
}

private struct RestTimerBar: View {
    let model: GymSessionModel

    var body: some View {
        if let timer = model.restTimer {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let remaining = timer.remaining(at: context.date)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Rest")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(verbatim: Formatters.duration(seconds: remaining.rounded(.up)))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(remaining > 0 ? Color.primary : Color.green)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    Button {
                        model.extendRest()
                    } label: {
                        Text("+30 s")
                            .font(.headline)
                            .frame(minWidth: 64, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        model.skipRest()
                    } label: {
                        Text(remaining > 0 ? "Skip" : "Close")
                            .font(.headline)
                            .frame(minWidth: 64, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 20))
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    let container = try! PersistenceController.makeContainer(inMemory: true)
    try! ExerciseSeeder.seedIfNeeded(in: container.mainContext)
    let model = GymSessionModel.start(
        in: container.mainContext, notifier: NoOpRestNotifier(), restDuration: 120
    )
    let exercise = try! container.mainContext.fetch(FetchDescriptor<Exercise>()).first!
    model.addExercise(exercise)
    return GymSessionView(model: model, onClose: {})
        .modelContainer(container)
}
