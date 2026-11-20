import XCTest

/// Fork builds compare their version with the original's latest release and only show it.
final class UpstreamReleaseTests: XCTestCase {
    func testLaterVersionsAreNewer() {
        XCTAssertTrue(UpstreamRelease.isNewer("v1.19", than: "1.18.1"))
        XCTAssertTrue(UpstreamRelease.isNewer("1.18.2", than: "1.18.1"))
        XCTAssertTrue(UpstreamRelease.isNewer("1.18.10", than: "1.18.9"))
        XCTAssertTrue(UpstreamRelease.isNewer("2.0", than: "1.99.99"))
    }

    func testSameOrEarlierVersionIsNotNewer() {
        XCTAssertFalse(UpstreamRelease.isNewer("v1.18.1", than: "1.18.1"))
        XCTAssertFalse(UpstreamRelease.isNewer("1.18", than: "1.18.0"))
        XCTAssertFalse(UpstreamRelease.isNewer("1.17", than: "1.18.1"))
        // A fork's own tag of the same version is not a new version of the original.
        XCTAssertFalse(UpstreamRelease.isNewer("v1.18.1-1", than: "1.18.1"))
    }

    func testVersionNumbers() {
        XCTAssertEqual(UpstreamRelease.numbers("v1.18.1"), [1, 18, 1])
        XCTAssertEqual(UpstreamRelease.numbers("1.18.1-1"), [1, 18, 1])
        XCTAssertEqual(UpstreamRelease.plainVersion(" V2.0 "), "2.0")
    }

    func testReadsGitHubsLatestRelease() throws {
        let json = """
        {"tag_name": "v1.19", "name": "Blitztext 1.19", "html_url": "https://github.com/cmagnussen/blitztext-app/releases/tag/v1.19",
         "draft": false, "prerelease": false, "assets": []}
        """
        let release = try UpstreamRelease(gitHubJSON: Data(json.utf8))
        XCTAssertEqual(release.version, "1.19")
        XCTAssertEqual(release.title, "Blitztext 1.19")
        XCTAssertEqual(release.url.absoluteString, "https://github.com/cmagnussen/blitztext-app/releases/tag/v1.19")
    }

    func testReleaseWithoutNameUsesItsTag() throws {
        let json = #"{"tag_name": "v1.19", "name": "", "html_url": "https://github.com/o/r/releases/tag/v1.19"}"#
        XCTAssertEqual(try UpstreamRelease(gitHubJSON: Data(json.utf8)).title, "v1.19")
    }

    func testLatestReleaseAddress() {
        XCTAssertEqual(
            UpstreamRelease.latestURL(repository: "cmagnussen/blitztext-app")?.absoluteString,
            "https://api.github.com/repos/cmagnussen/blitztext-app/releases/latest"
        )
    }
}
