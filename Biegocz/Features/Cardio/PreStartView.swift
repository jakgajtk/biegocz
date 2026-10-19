import SwiftUI

struct PreStartView: View {
    let model: PreStartModel
    let onStart: () -> Void
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isConfirmingWeakSignal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: model.type.systemImage)
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(model.type.title)
                    .font(.largeTitle.weight(.bold))

                if model.authorization == .denied {
                    VStack(spacing: 12) {
                        Text("Location access is off")
                            .font(.headline)
                        Text("Allow location access in Settings to record your route and distance.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                } else {
                    GPSQualityBadge(quality: model.quality)
                }

                Spacer()

                Button {
                    if model.quality == .poor || model.quality == .none {
                        isConfirmingWeakSignal = true
                    } else {
                        onStart()
                    }
                } label: {
                    Text("Start")
                        .font(.title.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.authorization != .authorized)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .task {
                await model.start()
            }
            .confirmationDialog(
                "GPS signal is weak",
                isPresented: $isConfirmingWeakSignal,
                titleVisibility: .visible
            ) {
                Button("Start anyway", action: onStart)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Distance may be inaccurate until the signal improves.")
            }
        }
    }
}

private struct GPSQualityBadge: View {
    let quality: GPSQuality

    var body: some View {
        HStack(spacing: 10) {
            if quality == .none {
                ProgressView()
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
            }
            Text(label)
                .font(.title3.weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.fill.tertiary, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch quality {
        case .none: .secondary
        case .poor: .red
        case .ok: .orange
        case .good: .green
        }
    }

    private var label: LocalizedStringKey {
        switch quality {
        case .none: "Searching for GPS…"
        case .poor: "GPS: poor"
        case .ok: "GPS: OK"
        case .good: "GPS: good"
        }
    }
}
