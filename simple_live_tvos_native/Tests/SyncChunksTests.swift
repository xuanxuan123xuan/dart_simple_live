import XCTest
@testable import SimpleLiveTVOS

final class SyncChunksTests: XCTestCase {
    private func header(_ index: Int, _ start: Int, _ end: Int, total: Int = 3) throws -> SyncChunk {
        try SyncChunk(fields: ["chunkIndex": index, "chunkTotal": 2, "itemStart": start,
                               "itemEnd": end, "itemTotal": total])
    }

    func testCommitsOnlyAfterCompleteDartSequence() throws {
        var chunks = SyncChunks()
        let first = try chunks.receive(header(1, 0, 2), data: Data("[1,2]".utf8), overwrite: true, key: "phone")
        guard case .partial(index: 1, total: 2) = first else { return XCTFail("First chunk must remain pending") }
        XCTAssertThrowsError(try chunks.receive(header(2, 2, 3), data: Data("[3]".utf8), overwrite: false, key: "other"))
        let last = try chunks.receive(header(2, 2, 3), data: Data("[3]".utf8), overwrite: false, key: "phone")
        guard case let .complete(rows, overwrite) = last else { return XCTFail("Expected complete transfer") }
        XCTAssertEqual(rows as? [Int], [1, 2, 3])
        XCTAssertTrue(overwrite)
        XCTAssertThrowsError(try chunks.receive(header(2, 2, 3), data: Data("[3]".utf8), overwrite: false, key: "phone"))
    }

    func testOverlappingTransfersFromTheSamePeerNeverMix() throws {
        var chunks = SyncChunks()
        let original = try header(1, 0, 2)
        _ = try chunks.receive(original, data: Data("[1,2]".utf8), overwrite: false, key: "phone")
        XCTAssertThrowsError(try chunks.receive(original, data: Data("[4,5]".utf8), overwrite: false, key: "phone"))
        XCTAssertThrowsError(try chunks.receive(header(2, 2, 3), data: Data("[3]".utf8), overwrite: false, key: "phone"))
        XCTAssertThrowsError(try SyncChunk(fields: ["chunkIndex": true]))
    }

    func testInvalidOrExpiredChunkCannotApplyEarlierRows() throws {
        var chunks = SyncChunks()
        let now = Date()
        _ = try chunks.receive(header(1, 0, 2), data: Data("[1,2]".utf8), overwrite: true, key: "phone", now: now)
        XCTAssertThrowsError(try chunks.receive(header(2, 1, 3), data: Data("[2,3]".utf8), overwrite: false, key: "phone"))
        XCTAssertThrowsError(try chunks.receive(header(2, 2, 3), data: Data("[3]".utf8), overwrite: false, key: "phone"))
        _ = try chunks.receive(header(1, 0, 2), data: Data("[1,2]".utf8), overwrite: true, key: "phone", now: now)
        XCTAssertThrowsError(try chunks.receive(header(2, 2, 3), data: Data("[3]".utf8), overwrite: false,
                                               key: "phone", now: now.addingTimeInterval(46)))
    }
}
