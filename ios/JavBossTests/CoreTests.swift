import XCTest
@testable import JavBoss

final class CoreTests: XCTestCase {
    func testServerURLNormalization() {
        let session = Session()
        XCTAssertEqual(session.normalizedServerUrl(" 192.168.1.2:8080/// "), "http://192.168.1.2:8080")
        XCTAssertEqual(session.normalizedServerUrl("https://example.test/"), "https://example.test")
    }

    func testPlaybackProgress() {
        XCTAssertEqual(
            PlaybackProgress.total(initialWatchedMs: 20_000, resumePositionMs: 20_000, positionMs: 35_000),
            35_000
        )
        XCTAssertNil(PlaybackProgress.total(initialWatchedMs: 20_000, resumePositionMs: 20_000, positionMs: 20_000))
    }

    func testErrorBodyParsing() {
        let data = #"{"message":"bad request"}"#.data(using: .utf8)
        XCTAssertEqual(APIClient.parseErrorBody(data), "bad request")
    }
}
