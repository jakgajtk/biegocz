import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.weightStepKey) private var weightStep = AppSettings.defaultWeightStep
    @AppStorage(AppSettings.restDurationKey) private var restDuration = AppSettings.defaultRestDuration

    @State private var exportedFiles: ExportedFiles?
    @State private var exportFailed = false

    var body: some View {
        Form {
            Section("Gym") {
                Picker("Weight step", selection: $weightStep) {
                    ForEach(AppSettings.weightStepOptions, id: \.self) { step in
                        Text(verbatim: Formatters.weight(kg: step)).tag(step)
                    }
                }
                Stepper(
                    value: $restDuration,
                    in: AppSettings.restDurationRange,
                    step: AppSettings.restDurationStep
                ) {
                    LabeledContent("Default rest", value: Formatters.duration(seconds: Double(restDuration)))
                }
            }

            Section {
                Button("Export data", systemImage: "square.and.arrow.up", action: export)
            } header: {
                Text("Data")
            } footer: {
                Text("Exports everything as JSON, plus a CSV of all gym sets.")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.appVersion)
            }
        }
        .navigationTitle("Settings")
        .sheet(item: $exportedFiles) { files in
            ShareSheet(items: files.urls)
                .ignoresSafeArea()
        }
        .alert("Export failed", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data could not be exported. Please try again.")
        }
    }

    private func export() {
        do {
            exportedFiles = ExportedFiles(urls: try DataExporter.writeExportFiles(from: modelContext))
        } catch {
            exportFailed = true
        }
    }
}

private struct ExportedFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(try! PersistenceController.makeContainer(inMemory: true))
}
