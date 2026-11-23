import Foundation

/// Where the downloaded models live (speech recognition, the local language model, the
/// speaker models of meetings): inside Application Support by default, or in a folder chosen
/// under Einstellungen > Modelle > Speicherort, for example on an external SSD when the Mac
/// has little room. Foundation only, so the tests compile it.
enum ModelStorageLocation {
    static let defaultsKey = "ModelStorageDirectory"
    /// Made inside the folder the user picks, so the models do not spill into the top of a drive.
    static let folderName = "DoMa Talk Modelle"

    /// The folder chosen in the settings; nil for the default inside Application Support.
    static var customDirectoryURL: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: defaultsKey), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.standardizedFileURL.path, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }

    /// The models folder inside the folder the user picked.
    static func target(inPicked picked: URL) -> URL {
        picked.lastPathComponent == folderName
            ? picked
            : picked.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The external drive `url` lies on, e.g. "SSD" for /Volumes/SSD/…; nil on the Mac's own disk.
    static func driveName(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[0] == "/", parts[1] == "Volumes" else { return nil }
        return parts[2]
    }

    /// The drive of `url` is connected. An external drive is mounted at /Volumes/<Name>; while
    /// it is unplugged that folder is missing, and creating the models folder anyway would put
    /// the downloads on the Mac's own disk instead.
    static func isReachable(_ url: URL, isMountedVolume: (String) -> Bool = ModelStorageLocation.isMountedVolume) -> Bool {
        guard let drive = driveName(of: url) else { return true }
        return isMountedVolume("/Volumes/" + drive)
    }

    /// The chosen folder is on a drive that is not connected right now.
    static var isUnavailable: Bool {
        guard let url = customDirectoryURL else { return false }
        return !isReachable(url)
    }

    /// What to tell the user while the drive is missing.
    static var unavailableMessage: String? {
        guard isUnavailable, let url = customDirectoryURL else { return nil }
        let drive = driveName(of: url) ?? url.path
        return "Die Modelle liegen auf \u{201E}\(drive)\u{201C}, das gerade nicht verbunden ist. Schlie\u{00DF}e das Laufwerk an oder w\u{00E4}hle unter Einstellungen > Modelle einen anderen Speicherort."
    }

    /// `path` is the top of a mounted volume, not just a folder of that name.
    static func isMountedVolume(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let volume = try? url.resourceValues(forKeys: [.volumeURLKey]).volume else { return false }
        return volume.standardizedFileURL.path == url.standardizedFileURL.path
    }
}

/// Moves the models from one folder to another, all or nothing: everything is copied first,
/// and only when every item arrived are the originals removed. A move that fails leaves the
/// old folder as it was, so the setting can stay on it.
enum ModelStorageMove {
    enum Failure: LocalizedError, Equatable {
        case insideSource
        case notEnoughSpace(needed: Int64, available: Int64)

        var errorDescription: String? {
            switch self {
            case .insideSource:
                return "Dieser Ordner liegt im bisherigen Modellordner. Bitte einen Ordner au\u{00DF}erhalb w\u{00E4}hlen."
            case .notEnoughSpace(let needed, let available):
                let format = ByteCountFormatter()
                return "Am neuen Ort ist nicht genug Platz: n\u{00F6}tig \(format.string(fromByteCount: needed)), frei \(format.string(fromByteCount: available))."
            }
        }
    }

    /// Unfinished downloads are not worth carrying over.
    static let skippedItems: Set<String> = ["downloads"]

    /// Moves every item of `source` into `destination`. An item already at the destination is
    /// replaced, since `source` holds what the app used. Nothing to move is fine.
    static func move(
        from source: URL,
        to destination: URL,
        availableSpace: (URL) -> Int64? = ModelStorageMove.availableSpace(at:)
    ) throws {
        let fileManager = FileManager.default
        let from = source.standardizedFileURL.resolvingSymlinksInPath()
        let to = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard from.path != to.path else { return }
        guard !to.path.hasPrefix(from.path + "/") else { throw Failure.insideSource }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        let carried = items.filter { !skippedItems.contains($0.lastPathComponent) }

        let needed = carried.reduce(Int64(0)) { $0 + size(of: $1) }
        if needed > 0, let available = availableSpace(destination), available < needed {
            throw Failure.notEnoughSpace(needed: needed, available: available)
        }

        var copied: [URL] = []
        do {
            for item in carried {
                let target = destination.appendingPathComponent(item.lastPathComponent)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: item, to: target)
                copied.append(target)
            }
        } catch {
            for target in copied { try? fileManager.removeItem(at: target) }
            throw error
        }

        for item in items { try? fileManager.removeItem(at: item) }
        if (try? fileManager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? fileManager.removeItem(at: source)
        }
    }

    /// Bytes of all files below `url` (a file or a folder).
    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func bytes(_ item: URL) -> Int64 {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return 0 }
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total = bytes(url)
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let item as URL in walker {
                total += bytes(item)
            }
        }
        return total
    }

    static func availableSpace(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
}
