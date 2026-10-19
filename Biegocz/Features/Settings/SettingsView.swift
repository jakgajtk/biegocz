import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.weightStepKey) private var weightStep = AppSettings.defaultWeightStep
    @AppStorage(AppSettings.restDurationKey) private var restDuration = AppSettings.defaultRestDuration
    @AppStorage(AppSettings.autoPauseRunKey) private var autoPauseRun = AppSettings.defaultAutoPauseRun
    @AppStorage(AppSettings.autoPauseRideKey) private var autoPauseRide = AppSettings.defaultAutoPauseRide

    @State private var exportedFiles: ExportedFiles?
    @State private var exportFailed = false
    @State private var isImporting = false
    @State private var importResult: DataImporter.Result?
    @State private var importFailed = false

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
                Toggle("Auto-pause runs", isOn: $autoPauseRun)
                Toggle("Auto-pause rides", isOn: $autoPauseRide)
            } header: {
                Text("Run and ride")
            } footer: {
                Text("Pauses when you stop moving and resumes when you move again.")
            }

            Section {
                Button("Export data", systemImage: "square.and.arrow.up", action: export)
                Button("Import data", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Exports everything as JSON, plus a CSV of all gym sets. Importing a JSON export adds what's missing and never changes or deletes existing data.")
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
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .alert("Export failed", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data could not be exported. Please try again.")
        }
        .alert("Import finished", isPresented: Binding(
            get: { importResult != nil },
            set: { if !$0 { importResult = nil } }
        ), presenting: importResult) { _ in
            Button("OK", role: .cancel) {}
        } message: { result in
            Text(verbatim: [
                String(localized: "Added \(result.activitiesAdded) activities."),
                String(localized: "Skipped \(result.activitiesSkipped) already in the app."),
            ].joined(separator: "\n"))
        }
        .alert("Import failed", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This file isn't a Biegocz export or was made by a newer version of the app.")
        }
    }

    private func export() {
        do {
            exportedFiles = ExportedFiles(urls: try DataExporter.writeExportFiles(from: modelContext))
        } catch {
            exportFailed = true
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            importFailed = true
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            importResult = try DataImporter.importData(data, into: modelContext)
        } catch {
            importFailed = true
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
