import AppKit
import SwiftUI

/// Einstellungen > Modelle > Speicherort: where the downloaded models live. A Mac with little
/// room can keep them on an external drive; the models already there move along.
struct ModelStorageSection: View {
    @Bindable var appState: AppState

    @State private var isMoving = false
    @State private var usedBytes: Int64?
    @State private var message: String?
    @State private var failed = false

    private var folder: URL {
        _ = appState.modelStorageRevision
        return AppSupportPaths.localModelsDirectoryURL
    }

    private var isCustom: Bool {
        _ = appState.modelStorageRevision
        return ModelStorageLocation.customDirectoryURL != nil
    }

    /// No download and no dictation may use the folder while it moves.
    private var isBusy: Bool {
        isMoving || appState.isDownloadingLocalModel || LocalModelStore.shared.isDownloading
            || appState.activeWorkflow?.phase.isActive == true || appState.meeting.isRecording || appState.meeting.isProcessing
    }

    var body: some View {
        SettingsSection(title: "Speicherort") {
            Text("Die Modelle brauchen Platz: die Spracherkennung etwa 0,6 GB, das lokale KI-Modell f\u{00FC}r Meetings mehrere GB. Auf einem Mac mit wenig Speicher kannst du sie auf ein externes Laufwerk legen, vorhandene Modelle ziehen mit um. Das Laufwerk muss dann angeschlossen sein, wenn du diktierst.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: isCustom ? "externaldrive" : "internaldrive")
                    .font(.ui(11, .semibold))
                    .foregroundStyle(.secondary)
                Text(displayPath)
                    .font(.ui(12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder.path)
                if let usedBytes, usedBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file))
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let unavailable = ModelStorageLocation.unavailableMessage {
                Text(unavailable)
                    .font(.ui(12))
                    .foregroundStyle(BlitztextTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Ordner w\u{00E4}hlen \u{2026}") { chooseFolder() }
                    .controlSize(.small)
                    .disabled(isBusy)
                if isCustom {
                    Button("Zur\u{00FC}ck auf diesen Mac") { move(to: nil) }
                        .controlSize(.small)
                        .disabled(isBusy)
                }
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                .controlSize(.small)
                .disabled(!FileManager.default.fileExists(atPath: folder.path))
            }

            if isMoving {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Modelle werden verschoben \u{2026} Bei mehreren GB dauert das einige Minuten.")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let message {
                Text(message)
                    .font(.ui(12))
                    .foregroundStyle(failed ? BlitztextTheme.danger : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: appState.modelStorageRevision) { await measure() }
    }

    /// The folder with ~ for the home folder, e.g. "~/Library/Application Support/Blitztext/models".
    private var displayPath: String {
        let path = folder.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private func measure() async {
        let folder = folder
        usedBytes = await Task.detached(priority: .utility) {
            ModelStorageMove.size(of: folder)
        }.value
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Speicherort der Modelle"
        panel.message = "W\u{00E4}hle einen Ordner, zum Beispiel auf deiner externen SSD. DoMa Talk legt darin den Ordner \u{201E}\(ModelStorageLocation.folderName)\u{201C} an."
        panel.prompt = "Hierhin verschieben"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        move(to: ModelStorageLocation.target(inPicked: picked))
    }

    /// Moves the models to `destination`, nil for the default folder on this Mac. The setting
    /// changes only once everything arrived; a failed move leaves it on the old folder.
    private func move(to destination: URL?) {
        guard !isBusy else { return }
        let source = AppSupportPaths.localModelsDirectoryURL
        let target = destination ?? AppSupportPaths.defaultLocalModelsDirectoryURL
        if let destination, !ModelStorageLocation.isReachable(destination) {
            failed = true
            message = "Das Laufwerk ist nicht verbunden."
            return
        }
        isMoving = true
        message = nil
        failed = false
        Task {
            let error: String? = await Task.detached(priority: .userInitiated) {
                do {
                    // An unplugged drive has nothing to move: the setting just changes.
                    if ModelStorageLocation.isReachable(source) {
                        try ModelStorageMove.move(from: source, to: target)
                    } else {
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            isMoving = false
            if let error {
                failed = true
                message = "Verschieben hat nicht geklappt: \(error) Die Modelle bleiben, wo sie waren."
                return
            }
            ModelStorageLocation.customDirectoryURL = destination
            appState.modelStorageChanged()
            message = appState.selectedLocalModelIsInstalled
                ? "Fertig. Die Modelle liegen jetzt hier."
                : "Fertig. Am neuen Ort fehlt noch die Spracherkennung; lade sie oben unter Spracherkennung."
        }
    }
}
