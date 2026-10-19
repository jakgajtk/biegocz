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
            if model.entries.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        IconBadge(systemImage: "dumbbell.fill", tint: .gymTint, size: 64)
                            .symbolEffect(.bounce, options: .nonRepeating)
                        Text("Let's get started")
                            .font(.title2.weight(.bold))
                        Text("Add your first exercise. The timer is already running.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(model.entries) { entry in
                ExerciseSection(model: model, entry: entry, focusedField: $focusedField)
            }

            Section {
                Button {
                    Haptics.tap()
                    isPickingExercise = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .buttonStyle(.prominent(height: 56))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Note") {
                TextField("Add a note", text: Bindable(model.activity).note, axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit { model.save() }
                    .cardRow()
            }
        }
        .listStyle(.insetGrouped)
        .appListStyle()
        .animation(Design.spring, value: model.entries.map(\.id))
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Design.bouncy, value: model.restTimer != nil)
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
                Haptics.tap()
                withAnimation(Design.spring) { model.addSet(to: entry) }
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .cardRow()
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: entry.exercise?.displayName ?? "")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        .lineLimit(2)
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

/// Floating rest countdown with a progress ring. Buzzes when rest is over.
private struct RestTimerBar: View {
    let model: GymSessionModel

    var body: some View {
        if let timer = model.restTimer {
            TimelineView(.animation(minimumInterval: 0.1)) { context in
                RestTimerContent(
                    timer: timer,
                    now: context.date,
                    onExtend: {
                        Haptics.tap()
                        model.extendRest()
                    },
                    onSkip: {
                        Haptics.tap()
                        model.skipRest()
                    }
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}

private struct RestTimerContent: View {
    let timer: RestTimer
    let now: Date
    let onExtend: () -> Void
    let onSkip: () -> Void

    private var remaining: TimeInterval { timer.remaining(at: now) }
    private var isDone: Bool { remaining <= 0 }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.cardFill, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: timer.fractionRemaining(at: now))
                    .stroke(isDone ? Color.success : Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: isDone ? "checkmark" : "timer")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isDone ? Color.success : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 0) {
                Text(isDone ? "Time for your next set" : "Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(verbatim: Formatters.duration(seconds: remaining.rounded(.up)))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Design.spring, value: Int(remaining.rounded(.up)))
                    .foregroundStyle(isDone ? Color.success : Color.primary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            Button(action: onExtend) {
                Text("+30 s")
                    .font(.headline)
                    .frame(minWidth: 60, minHeight: 50)
                    .background(.cardFill, in: .capsule)
            }
            .buttonStyle(.pressable)

            Button(action: onSkip) {
                Text(isDone ? "Close" : "Skip")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 60, minHeight: 50)
                    .padding(.horizontal, 4)
                    .background(isDone ? Color.success : Color.accentColor, in: .capsule)
            }
            .buttonStyle(.pressable)
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: Design.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .onChange(of: isDone) { _, done in
            if done { Haptics.success() }
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
