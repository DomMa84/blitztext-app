import Combine
import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class AppUpdateService {
    private let updaterController: SPUStandardUpdaterController
    private let updaterSettings: SPUUpdaterSettings
    private var cancellables: Set<AnyCancellable> = []
    private var didStartUpdater = false

    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false {
        didSet {
            guard oldValue != automaticallyChecksForUpdates else { return }
            updaterSettings.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var automaticallyDownloadsUpdates = false {
        didSet {
            guard oldValue != automaticallyDownloadsUpdates else { return }
            updaterSettings.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    var statusText: String

    // MARK: Fork builds: show the original's new versions, never install them

    /// The original repository of a fork (Info.plist `BlitztextUpstreamRepository`, e.g.
    /// "cmagnussen/blitztext-app"). Such a build never installs the original's versions, which
    /// would replace the fork's own changes; it only says that a newer one exists.
    let upstreamRepository: String? = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "BlitztextUpstreamRepository") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }()

    /// A version of the original newer than this build; nil when there is none or nothing was checked yet.
    var upstreamRelease: UpstreamRelease?
    var upstreamCheckedAt: Date?
    var upstreamCheckError: String?
    var isCheckingUpstream = false

    /// The version whose notice the user hid on the main page ("Ausblenden").
    var dismissedUpstreamVersion: String? {
        didSet { UserDefaults.standard.set(dismissedUpstreamVersion, forKey: Self.dismissedUpstreamKey) }
    }

    /// Look at the original once a day while Blitztext runs.
    var checksUpstreamDaily = true {
        didSet {
            guard oldValue != checksUpstreamDaily else { return }
            UserDefaults.standard.set(checksUpstreamDaily, forKey: Self.dailyUpstreamKey)
            if checksUpstreamDaily { startUpstreamChecks() } else { stopUpstreamChecks() }
        }
    }

    private var upstreamTask: Task<Void, Never>?
    private static let dismissedUpstreamKey = "UpstreamDismissedVersion"
    private static let dailyUpstreamKey = "UpstreamCheckDaily"
    private static let upstreamInterval: Duration = .seconds(24 * 60 * 60)

    private let feedURLString: String
    private let publicKey: String

    init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterSettings = SPUUpdaterSettings(hostBundle: .main)
        self.feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        self.publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        self.automaticallyChecksForUpdates = updaterSettings.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updaterSettings.automaticallyDownloadsUpdates
        self.dismissedUpstreamVersion = UserDefaults.standard.string(forKey: Self.dismissedUpstreamKey)
        self.checksUpstreamDaily = UserDefaults.standard.object(forKey: Self.dailyUpstreamKey) as? Bool ?? true
        self.statusText = Self.configurationHint(
            isConfigured: Self.isConfigured(
                feedURLString: feedURLString,
                publicKey: publicKey
            )
        )
        bindUpdaterState()
    }

    var isConfigured: Bool {
        Self.isConfigured(feedURLString: feedURLString, publicKey: publicKey)
    }

    /// Blackboat's Jamf installs and updates Blitztext on its Macs. Sparkle stays off there, so
    /// nobody gets a second update channel or an admin password prompt; this also applies to a
    /// copy installed by hand on such a Mac. Other managed Macs keep Sparkle.
    let isManagedByDeviceManagement = BlitztextInstallLocationService.isManagedByJamf

    /// Sparkle runs: the build has a feed and key, no device management does the job, and it
    /// is no fork's build (those only show the original's versions, `notifiesOnly`).
    var updatesInApp: Bool {
        isConfigured && !isManagedByDeviceManagement && upstreamRepository == nil
    }

    /// A fork's build: new versions of the original are shown, never installed.
    var notifiesOnly: Bool {
        upstreamRepository != nil && !isManagedByDeviceManagement
    }

    /// The notice on the main page: a newer original version the user has not hidden.
    var showsUpstreamNotice: Bool {
        guard let upstreamRelease else { return false }
        return upstreamRelease.version != dismissedUpstreamVersion
    }

    var configurationHint: String {
        Self.configurationHint(isConfigured: isConfigured)
    }

    func startIfConfigured() {
        if notifiesOnly {
            startUpstreamChecks()
            return
        }
        guard updatesInApp, !didStartUpdater else { return }

        updaterController.startUpdater()
        didStartUpdater = true
        statusText = "DoMa Talk hält sich über Sparkle aktuell."
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        if notifiesOnly {
            Task { await checkUpstream() }
            return
        }
        guard updatesInApp else {
            statusText = configurationHint
            return
        }

        startIfConfigured()
        statusText = "Suche nach Updates …"
        NotificationCenter.default.post(name: .dismissPopover, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
    }

    /// Asks GitHub for the original's latest release and keeps it when it is newer than this
    /// build. Nothing is downloaded.
    func checkUpstream() async {
        guard let repository = upstreamRepository,
              let url = UpstreamRelease.latestURL(repository: repository),
              !isCheckingUpstream else { return }
        isCheckingUpstream = true
        defer { isCheckingUpstream = false }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let latest = try UpstreamRelease(gitHubJSON: data)
            upstreamRelease = UpstreamRelease.isNewer(latest.version, than: Self.currentVersion) ? latest : nil
            upstreamCheckError = nil
        } catch {
            upstreamCheckError = "Das Original war gerade nicht erreichbar. Sp\u{00E4}ter noch einmal versuchen."
        }
        upstreamCheckedAt = Date()
    }

    private func startUpstreamChecks() {
        guard notifiesOnly, checksUpstreamDaily, upstreamTask == nil else { return }
        upstreamTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkUpstream()
                try? await Task.sleep(for: Self.upstreamInterval)
            }
        }
    }

    private func stopUpstreamChecks() {
        upstreamTask?.cancel()
        upstreamTask = nil
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func bindUpdaterState() {
        canCheckForUpdates = updatesInApp

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }

    private static func isConfigured(feedURLString: String, publicKey: String) -> Bool {
        let normalizedFeedURL = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPublicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFeedURL.isEmpty,
              !normalizedPublicKey.isEmpty,
              URL(string: normalizedFeedURL) != nil,
              !normalizedFeedURL.contains("example.invalid"),
              normalizedPublicKey != "SPARKLE_PUBLIC_ED_KEY_NOT_CONFIGURED",
              normalizedPublicKey != "REPLACE_WITH_GENERATED_PUBLIC_KEY" else {
            return false
        }

        return true
    }

    private static func configurationHint(isConfigured: Bool) -> String {
        if isConfigured {
            return "Updates werden über den hinterlegten Sparkle-Feed verteilt."
        }
        return "Für Auto-Updates fehlen noch Feed-URL oder öffentlicher Sparkle-Key im Build."
    }
}
