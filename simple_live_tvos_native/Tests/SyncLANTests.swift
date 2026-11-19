import XCTest
@testable import SimpleLiveTVOS

final class SyncLANTests: XCTestCase {
    @MainActor
    func testDartHTTPChunksAcknowledgeOnlyAfterValidatedOverwrite() async throws {
        let suite = "SyncLANTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryStore(defaults: defaults)
        library.importBlockedWords(["existing"])
        let server = LANSync()
        let receiver = SyncReceiver(importer: SyncImporter(library: library))
        let selection = SyncSelection()
        func request(_ index: Int, overwrite: Bool) throws -> LANSyncRequest {
            let body = Data("[\"\(index)\"]".utf8)
            let start = index - 1
            let query = "overlay=\(overwrite ? 1 : 0)&chunkIndex=\(index)&chunkTotal=2&itemStart=\(start)&itemEnd=\(index)&itemTotal=2"
            let header = Data("POST /sync/blocked_word?\(query) HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            XCTAssertNil(try LANSyncRequest.parse(header + body.dropLast()))
            return try XCTUnwrap(LANSyncRequest.parse(header + body))
        }
        let first = await server.respond(try request(1, overwrite: true), peer: "phone",
                                         selection: selection, receiver: receiver)
        XCTAssertEqual(first["message"] as? String, "chunk received")
        XCTAssertEqual(library.blockedWords, ["existing"])
        let last = try request(2, overwrite: false)
        let pending = Task {
            await server.respond(last, peer: "phone", selection: selection, receiver: receiver)
        }
        for _ in 0..<20 where receiver.review == nil { await Task.yield() }
        XCTAssertEqual(receiver.review?.overwrite, true)
        XCTAssertEqual(library.blockedWords, ["existing"])
        receiver.answer(true)
        let result = await pending.value
        XCTAssertEqual(result["status"] as? Bool, true)
        XCTAssertEqual(library.blockedWords, ["1", "2"])
    }
}
