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
    @State private var isPicking = false
    @State private var importMode = ImportMode.backup
    @State private var importResult: DataImporter.Result?
    @State private var importFailed = false
    @State private var historyProgress: HistoryProgress?
    @State private var historyResult: HistoryImporter.Result?
    @State private var noActivityFiles = false
    @State private var historyFailed = false

    var body: some View {
        withPickers
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
            .alert("Import finished", isPresented: Binding(
                get: { historyResult != nil },
                set: { if !$0 { historyResult = nil } }
            ), presenting: historyResult) { _ in
                Button("OK", role: .cancel) {}
            } message: { result in
                Text(verbatim: historyLines(for: result).joined(separator: "\n"))
            }
            .alert("No activity files found", isPresented: $noActivityFiles) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Choose the unzipped Strava export, or a folder of GPX, TCX or FIT files.")
            }
            .alert("Import failed", isPresented: $historyFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your activities could not be imported. Please try again.")
            }
    }

    private var withPickers: some View {
        form
            .sheet(item: $exportedFiles) { files in
                ShareSheet(items: files.urls)
                    .ignoresSafeArea()
            }
            // One file importer for both modes: several on one view don't present reliably.
            .fileImporter(
                isPresented: $isPicking,
                allowedContentTypes: importMode == .history ? [.folder, .item] : [.json],
                allowsMultipleSelection: importMode == .history
            ) { result in
                switch importMode {
                case .backup: importFile(result.map { $0.first })
                case .history: importHistory(result)
                }
            }
            .alert("Export failed", isPresented: $exportFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your data could not be exported. Please try again.")
            }
    }

    private var form: some View {
        Form {
            Section("Gym") {
                Picker(selection: $weightStep) {
                    ForEach(AppSettings.weightStepOptions, id: \.self) { step in
                        Text(verbatim: Formatters.weight(kg: step)).tag(step)
                    }
                } label: {
                    SettingLabel(title: "Weight step", systemImage: "scalemass.fill", tint: .gymTint)
                }
                Stepper(
                    value: $restDuration,
                    in: AppSettings.restDurationRange,
                    step: AppSettings.restDurationStep
                ) {
                    LabeledContent {
                        Text(verbatim: Formatters.duration(seconds: Double(restDuration)))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(restDuration)))
                    } label: {
                        SettingLabel(title: "Default rest", systemImage: "timer", tint: .accentColor)
                    }
                }
            }
            .cardRow()

            Section {
                Toggle(isOn: $autoPauseRun) {
                    SettingLabel(title: "Auto-pause runs", systemImage: "figure.run", tint: .runTint)
                }
                Toggle(isOn: $autoPauseRide) {
                    SettingLabel(title: "Auto-pause rides", systemImage: "figure.outdoor.cycle", tint: .rideTint)
                }
            } header: {
                Text("Run and ride")
            } footer: {
                Text("Pauses when you stop moving and resumes when you move again.")
            }
            .cardRow()

            Section {
                Button(action: export) {
                    SettingLabel(title: "Export data", systemImage: "square.and.arrow.up", tint: .success)
                }
                Button {
                    pick(.backup)
                } label: {
                    SettingLabel(title: "Import data", systemImage: "square.and.arrow.down", tint: .warning)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Exports everything as JSON, plus a CSV of all gym sets. Importing a JSON export adds what's missing and never changes or deletes existing data.")
            }
            .cardRow()
            .disabled(historyProgress != nil)

            historySection

            Section {
                LabeledContent {
                    Text(verbatim: Bundle.main.appVersion)
                } label: {
                    SettingLabel(title: "Version", systemImage: "info", tint: .secondary)
                }
            }
            .cardRow()
        }
        .appListStyle()
        .tint(.accentColor)
        .sensoryFeedback(.selection, trigger: weightStep)
        .sensoryFeedback(.selection, trigger: restDuration)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: autoPauseRun)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: autoPauseRide)
        .animation(Design.spring, value: restDuration)
        .animation(Design.spring, value: historyProgress)
        .navigationTitle("Settings")
        .navigationBarBackButtonHidden(historyProgress != nil)
    }

    private var historySection: some View {
        Section {
            if let historyProgress {
                HistoryProgressRow(progress: historyProgress)
                    .transition(.opacity)
            } else {
                Button {
                    pick(.history)
                } label: {
                    SettingLabel(title: "Import from Strava or MapMyRun", systemImage: "map.fill", tint: .runTint)
                }
            }
        } header: {
            Text("Run and ride history")
        } footer: {
            Text("Choose the unzipped Strava export folder, or GPX, TCX or FIT files. Runs and rides are added with their maps; ones already in the app are skipped, and nothing is written to Health.")
        }
        .cardRow()
    }

    private func pick(_ mode: ImportMode) {
        importMode = mode
        isPicking = true
    }

    private func historyLines(for result: HistoryImporter.Result) -> [String] {
        var lines = [String(localized: "Added \(result.added) activities.")]
        if result.duplicates > 0 {
            lines.append(String(localized: "Skipped \(result.duplicates) already in the app."))
        }
        if result.skipped > 0 {
            lines.append(String(localized: "Skipped (other sports or no GPS): \(result.skipped)."))
        }
        if result.failed > 0 {
            lines.append(String(localized: "Couldn't read \(result.failed) files."))
        }
        return lines
    }

    private func importHistory(_ result: Result<[URL], Error>) {
        guard case .success(let picked) = result, !picked.isEmpty else { return }
        let accessing = picked.filter { $0.startAccessingSecurityScopedResource() }
        let files = ActivityFile.files(in: picked)
        guard !files.isEmpty else {
            accessing.forEach { $0.stopAccessingSecurityScopedResource() }
            noActivityFiles = true
            return
        }
        historyProgress = HistoryProgress(done: 0, total: files.count)
        Task {
            defer { accessing.forEach { $0.stopAccessingSecurityScopedResource() } }
            let result = try? await HistoryImporter.importFiles(files, into: modelContext) { done in
                historyProgress?.done = done
            }
            historyProgress = nil
            if let result {
                if result.added > 0 { Haptics.success() }
                historyResult = result
            } else {
                historyFailed = true
            }
        }
    }

    private func export() {
        do {
            exportedFiles = ExportedFiles(urls: try DataExporter.writeExportFiles(from: modelContext))
        } catch {
            exportFailed = true
        }
    }

    private func importFile(_ result: Result<URL?, Error>) {
        guard case .success(let url?) = result else {
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

/// Settings-style row label: a small tinted icon tile and a title.
private struct SettingLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: .rect(cornerRadius: 8, style: .continuous))
        }
    }
}

private enum ImportMode {
    /// A Biegocz JSON export.
    case backup
    /// Runs and rides from Strava, MapMyRun or other apps.
    case history
}

private struct HistoryProgress: Equatable {
    var done: Int
    var total: Int
}

private struct HistoryProgressRow: View {
    let progress: HistoryProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Importing \(progress.done) of \(progress.total)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(progress.done)))
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
        }
        .padding(.vertical, 4)
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
