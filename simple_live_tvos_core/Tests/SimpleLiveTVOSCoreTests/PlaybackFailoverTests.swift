import XCTest
@testable import SimpleLiveTVOSCore

final class PlaybackFailoverTests: XCTestCase {
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
