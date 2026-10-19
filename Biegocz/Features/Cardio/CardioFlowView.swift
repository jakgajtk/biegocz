import SwiftData
import SwiftUI

/// Full-screen flow for a run or ride: pre-start, live, then the saved activity.
struct CardioFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SessionCoordinator.self) private var coordinator

    var body: some View {
        if let setup = coordinator.cardioSetup {
            PreStartView(
                model: setup,
                onStart: { coordinator.startCardio(in: modelContext) },
                onCancel: { coordinator.cancelCardioSetup() }
            )
        } else if let session = coordinator.cardioSession {
            if session.isFinished {
                NavigationStack {
                    ActivityDetailView(activity: session.activity)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { coordinator.closeCardio() }
                            }
                        }
                }
                .onAppear { Haptics.success() }
            } else {
                CardioLiveView(model: session, onDiscard: { coordinator.closeCardio() })
            }
        }
    }
}
