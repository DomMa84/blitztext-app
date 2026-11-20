import XCTest

/// The models folder can move to another drive (Einstellungen > Modelle > Speicherort).
/// Every move test works in temporary folders of its own, never in Application Support.
final class ModelStorageLocationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("blitztext-test-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to relativePath: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ relativePath: String, in folder: URL) -> String? {
        (try? Data(contentsOf: folder.appendingPathComponent(relativePath))).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - Location

    func testPickedFolderGetsItsOwnModelsFolder() {
        let picked = URL(fileURLWithPath: "/Volumes/SSD", isDirectory: true)
        XCTAssertEqual(ModelStorageLocation.target(inPicked: picked).path, "/Volumes/SSD/Blitztext Modelle")
        // Picking that folder itself does not nest a second one.
        let again = URL(fileURLWithPath: "/Volumes/SSD/Blitztext Modelle", isDirectory: true)
        XCTAssertEqual(ModelStorageLocation.target(inPicked: again).path, again.path)
    }

    func testDriveNameOnlyForExternalDrives() {
        XCTAssertEqual(ModelStorageLocation.driveName(of: URL(fileURLWithPath: "/Volumes/SSD/Blitztext Modelle")), "SSD")
        XCTAssertEqual(ModelStorageLocation.driveName(of: URL(fileURLWithPath: "/Volumes/Daten 2/a/b")), "Daten 2")
        XCTAssertNil(ModelStorageLocation.driveName(of: URL(fileURLWithPath: "/Users/someone/Models")))
    }

    func testFolderOnUnpluggedDriveIsNotReachable() {
        let onSSD = URL(fileURLWithPath: "/Volumes/SSD/Blitztext Modelle")
        XCTAssertTrue(ModelStorageLocation.isReachable(onSSD, isMountedVolume: { $0 == "/Volumes/SSD" }))
        XCTAssertFalse(ModelStorageLocation.isReachable(onSSD, isMountedVolume: { _ in false }))
        // The Mac's own disk is always there.
        XCTAssertTrue(ModelStorageLocation.isReachable(root, isMountedVolume: { _ in false }))
    }

    func testPlainFolderIsNoMountedVolume() {
        // A folder of the drive's name is not the drive: downloads must not land in it.
        XCTAssertFalse(ModelStorageLocation.isMountedVolume(root.path))
        XCTAssertFalse(ModelStorageLocation.isMountedVolume("/Volumes/blitztext-no-such-drive-\(UUID().uuidString)"))
        XCTAssertTrue(ModelStorageLocation.isMountedVolume("/"))
    }

    // MARK: - Move

    func testMoveCarriesEveryModelAndClearsTheOldFolder() throws {
        let source = root.appendingPathComponent("old/models")
        let destination = root.appendingPathComponent("ssd/Blitztext Modelle")
        try write("weights", to: "parakeet/parakeet-ultra/Encoder.mlmodelc/weight.bin", in: source)
        try write("gemma", to: "llm/gemma-4-e4b/model.safetensors", in: source)
        try write("hidden", to: ".download-123", in: source)
        try write("half", to: "downloads/abc/partial.bin", in: source)

        try ModelStorageMove.move(from: source, to: destination, availableSpace: { _ in nil })

        XCTAssertEqual(read("parakeet/parakeet-ultra/Encoder.mlmodelc/weight.bin", in: destination), "weights")
        XCTAssertEqual(read("llm/gemma-4-e4b/model.safetensors", in: destination), "gemma")
        XCTAssertEqual(read(".download-123", in: destination), "hidden")
        // Unfinished downloads are left behind, and the old folder goes.
        XCTAssertNil(read("downloads/abc/partial.bin", in: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testMoveReplacesWhatTheDestinationHeld() throws {
        let source = root.appendingPathComponent("models")
        let destination = root.appendingPathComponent("elsewhere")
        try write("new", to: "parakeet/file.bin", in: source)
        try write("old", to: "parakeet/file.bin", in: destination)
        try write("other", to: "whisperkit/file.bin", in: destination)

        try ModelStorageMove.move(from: source, to: destination, availableSpace: { _ in nil })

        XCTAssertEqual(read("parakeet/file.bin", in: destination), "new")
        // A model only the destination had stays.
        XCTAssertEqual(read("whisperkit/file.bin", in: destination), "other")
    }

    func testNothingToMoveStillPreparesTheDestination() throws {
        let source = root.appendingPathComponent("missing")
        let destination = root.appendingPathComponent("new")
        try ModelStorageMove.move(from: source, to: destination, availableSpace: { _ in nil })
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isFolder))
        XCTAssertTrue(isFolder.boolValue)
    }

    func testMoveIntoItsOwnSubfolderIsRefused() throws {
        let source = root.appendingPathComponent("models")
        try write("weights", to: "parakeet/file.bin", in: source)
        XCTAssertThrowsError(try ModelStorageMove.move(from: source, to: source.appendingPathComponent("inner"))) { error in
            XCTAssertEqual(error as? ModelStorageMove.Failure, .insideSource)
        }
        XCTAssertEqual(read("parakeet/file.bin", in: source), "weights")
    }

    func testTooLittleRoomLeavesEverythingWhereItWas() throws {
        let source = root.appendingPathComponent("models")
        let destination = root.appendingPathComponent("small-drive")
        try write(String(repeating: "x", count: 10_000), to: "parakeet/file.bin", in: source)

        XCTAssertThrowsError(try ModelStorageMove.move(from: source, to: destination, availableSpace: { _ in 10 })) { error in
            guard case .notEnoughSpace = error as? ModelStorageMove.Failure else {
                return XCTFail("Expected notEnoughSpace, got \(error)")
            }
        }
        XCTAssertNotNil(read("parakeet/file.bin", in: source))
        XCTAssertNil(read("parakeet/file.bin", in: destination))
    }

    func testMoveToTheSameFolderChangesNothing() throws {
        let source = root.appendingPathComponent("models")
        try write("weights", to: "parakeet/file.bin", in: source)
        try ModelStorageMove.move(from: source, to: source, availableSpace: { _ in 0 })
        XCTAssertEqual(read("parakeet/file.bin", in: source), "weights")
    }
}
