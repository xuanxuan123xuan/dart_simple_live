import XCTest
@testable import SimpleLiveTVOSCore

final class PlaybackFailoverTests: XCTestCase {
    func testPreferredLineIsTriedFirstAndKeepsRemainingProviderOrder() throws {
        let first = PlaybackResource(url: URL(string: "https://a.example/live.m3u8")!, protocolKind: .hls, lineIndex: 3)
        let preferred = PlaybackResource(url: URL(string: "https://b.example/live.flv")!, protocolKind: .flv, lineIndex: 8)
        let last = PlaybackResource(url: URL(string: "https://c.example/live.m3u8")!, protocolKind: .hls, lineIndex: 12)
        var controller = PlaybackFailoverController()

        let attempt = try controller.begin(resources: [first, preferred, last], preferredLine: 8)
        XCTAssertEqual(attempt.resource, preferred)
        try controller.markPlaying(lineIndex: 8, generation: attempt.generation)
        XCTAssertEqual(controller.currentLine, 8)
        XCTAssertEqual(try controller.failCurrent(generation: attempt.generation).resource, first)
        try controller.markPlaying(lineIndex: 3, generation: attempt.generation)
        XCTAssertEqual(controller.currentLine, 3)
        XCTAssertEqual(try controller.failCurrent(generation: attempt.generation).resource, last)

        let missingLine = try controller.begin(resources: [first, preferred, last], preferredLine: 20)
        XCTAssertEqual(missingLine.resource, first)
    }

    func testFailoverKeepsOriginalOrderAndAdvancesGeneration() throws {
        let first = PlaybackResource(url: URL(string: "https://a.example/live.m3u8")!, protocolKind: .hls)
        let second = PlaybackResource(url: URL(string: "https://b.example/live.flv")!, protocolKind: .flv)
        var controller = PlaybackFailoverController()

        let attempt = try controller.begin(resources: [first, second])
        XCTAssertEqual(attempt.resource, first)
        let next = try controller.failCurrent(generation: attempt.generation)
        XCTAssertEqual(next.resource, second)
        XCTAssertEqual(next.generation, attempt.generation)
    }

    func testStaleGenerationCannotChangeState() throws {
        let resource = PlaybackResource(url: URL(string: "https://a.example/live.m3u8")!, protocolKind: .hls)
        var controller = PlaybackFailoverController()
        let attempt = try controller.begin(resources: [resource])
        controller.stop()

        XCTAssertThrowsError(try controller.markPlaying(lineIndex: 0, generation: attempt.generation)) { error in
            XCTAssertEqual(error as? PlaybackFailoverError, .staleGeneration)
        }
    }
}
