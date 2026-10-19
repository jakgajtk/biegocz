import SwiftUI

struct ActivityDetailView: View {
    let activity: Activity

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: Formatters.dateTime(activity.startDate))
                LabeledContent("Duration", value: Formatters.duration(seconds: activity.elapsedSeconds))
                if activity.type.isCardio {
                    LabeledContent("Distance", value: Formatters.distance(meters: activity.distanceMeters))
                    LabeledContent("Moving time", value: Formatters.duration(seconds: activity.movingSeconds))
                } else {
                    LabeledContent("Sets") {
                        Text("\(activity.completedSetCount) sets")
                    }
                    LabeledContent("Volume", value: Formatters.weight(kg: activity.totalVolumeKg))
                }
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

            if !activity.note.isEmpty {
                Section("Note") {
                    Text(verbatim: activity.note)
                }
            }
        }
        .navigationTitle(Text(activity.type.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
