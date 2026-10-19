import SwiftUI

struct ActivityDetailView: View {
    let activity: Activity

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                if activity.type.isCardio {
                    cardioContent
                } else {
                    gymContent
                }

                if !activity.note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Note", systemImage: "note.text")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(verbatim: activity.note)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .appearEffect(delay: 0.2)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationTitle(Text(activity.type.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hero

    private func hero<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: activity.type.systemImage)
                    .font(.headline)
                Text(verbatim: Formatters.dateTime(activity.startDate))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.75))
            content()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Design.heroGradient, in: .rect(cornerRadius: Design.cornerRadius, style: .continuous))
        .appearEffect()
    }

    // MARK: Gym

    @ViewBuilder
    private var gymContent: some View {
        hero {
            HStack {
                heroStat("Duration", Formatters.duration(seconds: activity.elapsedSeconds))
                Spacer()
                heroStat("Sets", activity.completedSetCount.formatted())
                Spacer()
                heroStat("Volume", Formatters.weight(kg: activity.totalVolumeKg))
            }
        }

        ForEach(Array(activity.sortedExercises.enumerated()), id: \.element.id) { index, entry in
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: entry.exercise?.displayName ?? "")
                    .font(.headline)
                ForEach(Array(entry.sortedSets.enumerated()), id: \.element.id) { setIndex, set in
                    HStack {
                        Text(verbatim: (setIndex + 1).formatted())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(.cardFill, in: .circle)
                            .accessibilityLabel(Text("Set \(setIndex + 1)"))
                        Spacer()
                        Text(verbatim: SetFormatting.summary(of: set, loggingType: entry.exercise?.loggingType ?? .weightReps))
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .appearEffect(delay: 0.05 * Double(min(index + 1, 6)))
        }
    }

    // MARK: Run and ride

    @ViewBuilder
    private var cardioContent: some View {
        let segments = activity.routeSegments

        hero {
            VStack(alignment: .leading, spacing: 0) {
                Text("Distance")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                Text(verbatim: Formatters.distance(meters: activity.distanceMeters))
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            HStack {
                heroStat("Moving time", Formatters.duration(seconds: activity.movingSeconds))
                Spacer()
                if activity.type == .run {
                    heroStat("Avg pace", paceText(averageSpeed))
                } else {
                    heroStat("Avg speed", averageSpeed.map { Formatters.speed(metersPerSecond: $0) } ?? "--")
                }
            }
        }

        if segments.contains(where: { $0.count > 1 }) {
            RouteMap(segments: segments, tint: activity.type.tint)
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: Design.cornerRadius, style: .continuous))
                .appearEffect(delay: 0.08)
        }

        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatView(title: "Elapsed time", value: Formatters.duration(seconds: activity.elapsedSeconds))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14)
                if let gain = activity.elevationGainMeters {
                    StatView(title: "Elevation gain (approx.)", value: Formatters.elevation(meters: gain))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 14)
                }
            }
        }
        .appearEffect(delay: 0.12)

        if activity.type == .run {
            let splits = Splits.perKilometer(segments: segments)
            if !splits.isEmpty {
                SplitsCard(splits: splits, tint: activity.type.tint)
                    .appearEffect(delay: 0.16)
            }
        }
    }

    private func heroStat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
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

/// Per-km splits with bars: longer bar = faster kilometer; the fastest is highlighted.
private struct SplitsCard: View {
    let splits: [Split]
    let tint: Color
    @State private var isShown = false

    var body: some View {
        let paces = splits.map(\.secondsPerKilometer)
        let fastest = paces.min() ?? 1
        let slowest = paces.max() ?? 1

        VStack(alignment: .leading, spacing: 12) {
            Text("Splits")
                .font(.headline)
            ForEach(splits, id: \.number) { split in
                let pace = split.secondsPerKilometer
                // Map pace to 45...100 % width so even slow splits get a visible bar.
                let fraction = slowest > fastest ? 0.45 + 0.55 * (slowest - pace) / (slowest - fastest) : 1
                HStack(spacing: 10) {
                    Group {
                        if split.distance < 999 {
                            Text(verbatim: Formatters.distance(meters: split.distance))
                        } else {
                            Text("Kilometer \(split.number)")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(width: 92, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    GeometryReader { geometry in
                        Capsule()
                            .fill(pace == fastest ? tint : tint.opacity(0.35))
                            .frame(width: geometry.size.width * (isShown ? fraction : 0))
                    }
                    .frame(height: 10)

                    Text(verbatim: Formatters.pace(secondsPerKilometer: pace))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
        .onAppear {
            withAnimation(Design.spring.delay(0.25)) { isShown = true }
        }
    }
}
