import Foundation

/// "Feedback senden": a new issue in this fork's GitHub repository with the facts that help to
/// understand a report filled in. People see everything and send it themselves on GitHub; the
/// app sends nothing and adds no logs. The original Blitztext mailed its team at Blackboat;
/// DoMa Talk is an independent fork, so its feedback goes to the fork and never to them.
enum FeedbackMail {
    static let repository = "DomMa84/blitztext-app"

    /// Where the feedback goes, as shown to people and copied when the browser cannot open.
    static var address: String { "https://github.com/\(repository)/issues" }

    /// - Parameter details: lines about this app's setup, e.g. speech model and shortcut mode.
    static func url(details: [String] = []) -> URL? {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let facts = [
            "App: DoMa Talk \(version) (Build \(build)) für \(platform)",
            "System: \(systemName) \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Gerät: \(deviceModel)",
        ] + details

        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Feedback: DoMa Talk \(version) (Build \(build))"),
            URLQueryItem(name: "body", value: "\n\n\n---\nBitte oberhalb der Linie schreiben. Diese Angaben helfen beim Nachvollziehen, du kannst sie auch löschen:\n" + facts.joined(separator: "\n")),
        ]
        return components?.url
    }

    private static var platform: String {
        #if os(macOS)
        return "Mac"
        #else
        return "iPhone"
        #endif
    }

    private static var systemName: String {
        #if os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }

    /// "iPhone17,5" or "Mac16,10, Apple M4": the model identifier, on the Mac with the chip.
    private static var deviceModel: String {
        #if os(macOS)
        let model = sysctl("hw.model") ?? "Mac"
        return [model, sysctl("machdep.cpu.brand_string")].compactMap { $0 }.joined(separator: ", ")
        #else
        return sysctl("hw.machine") ?? "iPhone"
        #endif
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
