import SwiftUI

struct ActivityDetailView: View {
    let activity: Activity

    var body: some View {
        List {
            if activity.type.isCardio {
                cardioSections
            } else {
                gymSections
            }

            if !activity.note.isEmpty {
                Section("Note") {
                    Text(verbatim: activity.note)
                }
            }
        }
        .navigationTitle(Text(activity.type.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Gym

    @ViewBuilder
    private var gymSections: some View {
        Section {
            LabeledContent("Date", value: Formatters.dateTime(activity.startDate))
            LabeledContent("Duration", value: Formatters.duration(seconds: activity.elapsedSeconds))
            LabeledContent("Sets") {
                Text("\(activity.completedSetCount) sets")
            }
            LabeledContent("Volume", value: Formatters.weight(kg: activity.totalVolumeKg))
        }

        ForEach(activity.sortedExercises) { entry in
            Section(entry.exercise?.displayName ?? "") {
                ForEach(Array(entry.sortedSets.enumerated()), id: \.element.id) { index, set in
                    LabeledContent {
                        Text(verbatim: SetFormatting.summary(of: set, loggingType: entry.exercise?.loggingType ?? .weightReps))
                            .monospacedDigit()
                    } label: {
                        Text("Set \(index + 1)")
                    }
                }
            }
        }
    }

    // MARK: Run and ride

    @ViewBuilder
    private var cardioSections: some View {
        let segments = activity.routeSegments
        if segments.contains(where: { $0.count > 1 }) {
            Section {
                RouteMap(segments: segments)
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
            }
        }

        Section {
            LabeledContent("Date", value: Formatters.dateTime(activity.startDate))
            LabeledContent("Distance", value: Formatters.distance(meters: activity.distanceMeters))
            LabeledContent("Moving time", value: Formatters.duration(seconds: activity.movingSeconds))
            LabeledContent("Elapsed time", value: Formatters.duration(seconds: activity.elapsedSeconds))
            if activity.type == .run {
                LabeledContent("Avg pace", value: paceText(averageSpeed))
            } else {
                LabeledContent("Avg speed", value: averageSpeed.map { Formatters.speed(metersPerSecond: $0) } ?? "--")
            }
        }

        if activity.type == .run {
            let splits = Splits.perKilometer(segments: segments)
            if !splits.isEmpty {
                Section("Splits") {
                    ForEach(splits, id: \.number) { split in
                        LabeledContent {
                            Text(verbatim: paceText(split.distance / split.duration))
                                .monospacedDigit()
                        } label: {
                            if split.distance < 999 {
                                Text(verbatim: Formatters.distance(meters: split.distance))
                            } else {
                                Text("Kilometer \(split.number)")
                            }
                        }
                    }
                }
            }
        }
    }

    private var averageSpeed: Double? {
        guard activity.movingSeconds > 0, activity.distanceMeters > 0 else { return nil }
        return activity.distanceMeters / activity.movingSeconds
    }

    private func paceText(_ speed: Double?) -> String {
        let pace = Formatters.pace(secondsPerKilometer: Pace.secondsPerKilometer(metersPerSecond: speed))
        return String(localized: "\(pace) /km")
    }
}
