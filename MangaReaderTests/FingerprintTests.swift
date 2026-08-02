import XCTest
@testable import MangaReader

final class FingerprintTests: XCTestCase {
    func testFolderFingerprintIsStableAndOrderAware() {
        let first = Fingerprint.folderFingerprint(imageFiles: [
            (name: "b.jpg", size: 10),
            (name: "a.jpg", size: 20)
        ])
        let second = Fingerprint.folderFingerprint(imageFiles: [
            (name: "a.jpg", size: 20),
            (name: "b.jpg", size: 10)
        ])
        let different = Fingerprint.folderFingerprint(imageFiles: [
            (name: "a.jpg", size: 99),
            (name: "b.jpg", size: 10)
        ])
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, different)
    }
}
