@testable import SimpleLiveTVOS
import SimpleLiveTVOSCore
import XCTest

final class DanmakuFilterTests: XCTestCase {
    func testBlockedWordsAndRepeatedTextFromOtherUsers() {
        var users = DanmakuFilter(.init(mode: .sameSender, window: 10, blockedWords: ["广告"]))
        XCTAssertFalse(users.allows(event("这是广告", from: "甲")))
        XCTAssertTrue(users.allows(event("直播\n好看", from: "甲")))
        XCTAssertFalse(users.allows(event("直播 好看", from: "甲")))
        XCTAssertTrue(users.allows(event("直播 好看", from: "乙")))
        var global = DanmakuFilter(.init(mode: .allSenders, window: 5))
        XCTAssertTrue(global.allows(event("同一句", from: "甲")))
        XCTAssertFalse(global.allows(event("同一句", from: "乙")))
        for index in 0..<5 { XCTAssertTrue(global.allows(event("新弹幕\(index)", from: "丙"))) }
        XCTAssertTrue(global.allows(event("同一句", from: "乙")))
    }

    func testDartDelimitedRulesMatchRawTextAndPlainWordsStayLiteral() {
        var filter = DanmakuFilter(.init(blockedWords: [#"/^广告\s{2}[0-9]+$/"#, "a.b", "//"]))
        XCTAssertFalse(filter.allows(event("广告  123", from: "甲")))
        XCTAssertTrue(filter.allows(event("广告 123", from: "甲")))
        XCTAssertTrue(filter.allows(event("转发广告  123", from: "甲")))
        XCTAssertTrue(filter.allows(event("axb", from: "甲")))
        XCTAssertFalse(filter.allows(event("a.b", from: "甲")))
        XCTAssertFalse(filter.allows(event("双斜线 //", from: "甲")))
    }

    @MainActor
    func testStoredRegexRulesAreAppliedAndInvalidImportsAreIgnored() throws {
        let suite = "blocked-regex-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        LibraryStore(defaults: defaults).importBlockedWords(["/广告[0-9]+/", "/[/"])
        var filter = DanmakuFilter(.init(blockedWords: LibraryStore(defaults: defaults).blockedWords))
        XCTAssertFalse(filter.allows(event("这是广告123", from: "甲")))
        XCTAssertTrue(filter.allows(event("显示原样 /[/", from: "甲")))
    }

    @MainActor
    func testEditableBlockedWordsArePersistedAndMergedWithoutDuplicates() throws {
        let suite = "blocked-words-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(defaults: defaults)
        store.importBlockedWords(["广告", "  ", " 广告 "])
        store.importBlockedWords(["剧透"])
        store.removeBlockedWord("广告")
        XCTAssertEqual(LibraryStore(defaults: defaults).blockedWords, ["剧透"])
    }

    private func event(_ message: String, from sender: String) -> DanmakuEvent {
        DanmakuEvent(id: UUID().uuidString, room: RoomKey(provider: .bilibili, roomId: "123"),
                     userName: sender, message: message, color: DanmakuColor(red: 255, green: 255, blue: 255))
    }
}
