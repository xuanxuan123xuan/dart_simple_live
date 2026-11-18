import XCTest
import SimpleLiveTVOSCore
@testable import SimpleLiveTVOS

final class NativeCoreClientTests: XCTestCase {
    func testProviderDescriptorIsIdentifiable() {
        let value = ProviderDescriptor(id: "bilibili", title: "哔哩哔哩", supportLabel: "HLS")
        XCTAssertEqual(value.id, "bilibili")
        XCTAssertEqual(value.title, "哔哩哔哩")
    }

    func testRoomIdentityIncludesProviderAndRoomId() {
        let bili = RoomDescriptor(
            provider: "bilibili",
            roomId: "100",
            title: "直播",
            cover: "",
            userName: "主播"
        )
        let douyu = RoomDescriptor(
            provider: "douyu",
            roomId: "100",
            title: "直播",
            cover: "",
            userName: "主播"
        )
        XCTAssertNotEqual(bili.key, douyu.key)
    }

    func testStreamProtocolNamesAreStable() {
        XCTAssertEqual(StreamProtocol.hls.rawValue, "hls")
        XCTAssertEqual(StreamProtocol.flv.rawValue, "flv")
        XCTAssertEqual(StreamProtocol.rtmp.rawValue, "rtmp")
    }
}
