import Foundation

/// The newest release of the original repository a fork's build comes from
/// (Info.plist `BlitztextUpstreamRepository`). The fork's build only says that it exists and
/// never installs it: the original's version would replace the fork's own changes.
/// Foundation only, so the tests compile it.
struct UpstreamRelease: Equatable {
    /// "1.19" for the tag "v1.19".
    let version: String
    let title: String
    /// The release page with its notes.
    let url: URL

    init(version: String, title: String, url: URL) {
        self.version = version
        self.title = title
        self.url = url
    }

    /// The GitHub API's answer for /repos/<owner>/<repo>/releases/latest.
    init(gitHubJSON data: Data) throws {
        struct Answer: Decodable {
            let tagName: String
            let name: String?
            let htmlURL: URL

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case name
                case htmlURL = "html_url"
            }
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        let name = answer.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            version: Self.plainVersion(answer.tagName),
            title: name.isEmpty ? answer.tagName : name,
            url: answer.htmlURL
        )
    }

    static func latestURL(repository: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// "v1.18.1" → "1.18.1".
    static func plainVersion(_ tag: String) -> String {
        var version = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = version.first, first == "v" || first == "V" {
            version.removeFirst()
        }
        return version
    }

    /// "1.18.1" → [1, 18, 1]. Anything after the digits of a part is left out, such as the
    /// "-1" of a fork's own tag "v1.18.1-1".
    static func numbers(_ version: String) -> [Int] {
        plainVersion(version).split(separator: ".").map { part in
            Int(part.prefix(while: \.isNumber)) ?? 0
        }
    }

    /// `candidate` is a later version than `current`; "1.18" and "1.18.0" are the same.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = numbers(candidate)
        let old = numbers(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
