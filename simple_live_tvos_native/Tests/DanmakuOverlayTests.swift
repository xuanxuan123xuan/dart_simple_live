import SimpleLiveTVOSCore
import UIKit
import XCTest
@testable import SimpleLiveTVOS

final class DanmakuOverlayTests: XCTestCase {
    @MainActor
    func testBurstFillsSeparateLanesAndLeavesClearanceBeforeReuse() throws {
        let surface = makeSurface()
        let start = 100.0
        for _ in 0..<20 { surface.display(event("测试弹幕"), now: start) }

        let lanes = surface.subviews
        XCTAssertGreaterThanOrEqual(lanes.count, 3)
        XCTAssertEqual(Set(lanes.map(\.frame.minY)).count, lanes.count)
        XCTAssertTrue(lanes.allSatisfy { $0.frame.maxY <= surface.bounds.height / 4 })
        let first = try XCTUnwrap(lanes.first)
        let speed = surface.bounds.width / 9

        surface.display(event("弹幕还未让开"), now: start + (first.bounds.width + 39) / speed)
        XCTAssertEqual(surface.subviews.count, lanes.count)

        surface.display(event("补入同一轨道"), now: start + (first.bounds.width + 41) / speed)
        XCTAssertEqual(surface.subviews.count, lanes.count + 1)
        XCTAssertEqual(surface.subviews.last?.frame.minY, first.frame.minY)
    }

    @MainActor
    func testOverlayShowsMessageContentAndCanClearActiveLanes() throws {
        let surface = makeSurface()
        surface.display(event("  \n "), now: 100)
        XCTAssertTrue(surface.subviews.isEmpty)

        surface.display(event("直播\n弹幕"), now: 100)
        let label = try XCTUnwrap(surface.subviews.first)
        XCTAssertFalse(surface.isUserInteractionEnabled)

        surface.clear()
        XCTAssertTrue(surface.subviews.isEmpty)
        surface.display(event("直播 弹幕"), now: 100)
        XCTAssertEqual(surface.subviews.first?.frame.minY, label.frame.minY)
        XCTAssertEqual(surface.subviews.first?.bounds.width, label.bounds.width)
    }

    func testBilibiliStickersPreserveTextAndRejectUnrelatedHosts() throws {
        var attributes = Array<Any>(repeating: NSNull(), count: 16)
        attributes[15] = ["extra": #"{"emots":{"[你好]":{"url":"//i0.hdslb.com/emote.png"},"[外站]":{"url":"https://hdslb.com.example/track"}}}"#]
        let message = "欢迎[你好][外站]"
        let url = try XCTUnwrap(URL(string: "https://i0.hdslb.com/emote.png"))
        XCTAssertEqual(BilibiliPacket.stickerSpans(message: message, attributes: attributes),
                       [.text("欢迎"), .image(url: url, fallbackText: "[你好]"), .text("[外站]")])
        XCTAssertFalse(DanmakuStickerURL.permits(URL(string: "https://i0.hdslb.com:8080/a")!))
        XCTAssertFalse(DanmakuStickerURL.permits(URL(string: "https://foo@i0.hdslb.com/a")!))
    }

    @MainActor
    func testStyleChangesLimitLanesAndReplaceActiveLabels() throws {
        let surface = makeSurface()
        surface.display(event("默认弹幕"), now: 100)
        let defaultHeight = try XCTUnwrap(surface.subviews.first?.bounds.height)

        surface.configure(DanmakuStyle(fontSize: 56, crossingSeconds: 6, opacity: 0.4,
                                      outlineWidth: 0, layout: .lines, lines: 2))
        XCTAssertTrue(surface.subviews.isEmpty)
        for _ in 0..<10 { surface.display(event("调大后"), now: 100) }
        XCTAssertEqual(surface.subviews.count, 2)
        for label in surface.subviews {
            XCTAssertGreaterThan(label.bounds.height, defaultHeight)
            XCTAssertEqual(label.alpha, 0.4, accuracy: 0.01)
        }
        surface.configure(DanmakuStyle(layout: .area, area: 0.5))
        for _ in 0..<20 { surface.display(event("半屏弹幕"), now: 100) }
        XCTAssertGreaterThan(surface.subviews.count, 2)
        XCTAssertTrue(surface.subviews.allSatisfy { $0.frame.maxY <= surface.bounds.height / 2 })
    }

    @MainActor
    func testOutlineKeepsSolidColoredGlyphsOnLightAndDarkBackgrounds() throws {
        let text = DanmakuTextView("弹幕测试！", font: .systemFont(ofSize: 36, weight: .semibold),
                                   color: UIColor(red: 1, green: 0.7, blue: 0.1, alpha: 1), maximumWidth: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: text.bounds, format: format)

        for background in [UIColor(white: 0.92, alpha: 1), UIColor(white: 0.25, alpha: 1)] {
            let image = renderer.image { context in
                background.setFill()
                context.fill(text.bounds)
                text.draw(text.bounds)
            }
            let cgImage = try XCTUnwrap(image.cgImage)
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let bitmap = try XCTUnwrap(CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                                                   bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: colorSpace,
                                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.draw(cgImage, in: text.bounds)
            let pixels = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
            var fill = 0
            var outline = 0
            for offset in stride(from: 0, to: bitmap.bytesPerRow * bitmap.height, by: 4) {
                let (red, green, blue) = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
                if red > 230, (150...210).contains(green), blue < 65 { fill += 1 }
                if red < 32, green < 32, blue < 32 { outline += 1 }
            }
            XCTAssertGreaterThan(fill, 150)
            XCTAssertGreaterThan(outline, 80)
        }
    }

    @MainActor
    private func makeSurface() -> DanmakuSurface {
        let surface = DanmakuSurface(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        surface.setNeedsLayout()
        surface.layoutIfNeeded()
        return surface
    }

    private func event(_ message: String) -> DanmakuEvent {
        DanmakuEvent(id: UUID().uuidString, room: RoomKey(provider: .bilibili, roomId: "123"), userName: "测试用户",
                     message: message, color: DanmakuColor(red: 255, green: 255, blue: 255))
    }
}
