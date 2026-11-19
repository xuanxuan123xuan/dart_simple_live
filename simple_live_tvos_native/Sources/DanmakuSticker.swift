import ImageIO
import SimpleLiveTVOSCore
import UIKit

/// Stickers are fetched from the provider CDN without a session cookie and rendered inside fixed-width slots.
@MainActor
final class DanmakuStickerLoader {
    static let shared = DanmakuStickerLoader()
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var failures: [URL: TimeInterval] = [:]

    private init() {
        cache.totalCostLimit = 8 * 1024 * 1024
        cache.countLimit = 128
    }

    func image(_ url: URL) async -> UIImage? {
        guard DanmakuStickerURL.permits(url) else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inFlight[url] { return await task.value }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastFailure = failures[url], now - lastFailure < 60 { return nil }
        guard inFlight.count < 4 else { return nil }
        let task = Task {
            try? await Self.fetch(url)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result, let image = result.cgImage {
            cache.setObject(result, forKey: url as NSURL, cost: image.height * image.bytesPerRow)
        } else {
            if failures.count >= 128 { failures = failures.filter { now - $0.value < 60 } }
            if failures.count < 128 { failures[url] = now }
        }
        return result
    }

    nonisolated private static func fetch(_ url: URL) async throws -> UIImage? {
        guard let data = try await DanmakuAssetRequest.data(from: url, limit: 256 * 1024, mimeTypePrefix: "image/"),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

enum DanmakuAssetRequest {
    private static let redirectGuard = DanmakuAssetRedirectGuard()
    private static let client: URLSession = {
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        settings.timeoutIntervalForRequest = 4
        settings.timeoutIntervalForResource = 6
        return URLSession(configuration: settings)
    }()

    static func data(from url: URL, limit: Int, mimeTypePrefix: String) async throws -> Data? {
        let (bytes, response) = try await client.bytes(for: URLRequest(url: url), delegate: redirectGuard)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType?.hasPrefix(mimeTypePrefix) == true, response.expectedContentLength <= limit else { return nil }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { return nil }
            data.append(byte)
        }
        return data
    }
}

private final class DanmakuAssetRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class DanmakuStickerLine: UIView {
    init(spans: [DanmakuSpan], font: UIFont, color: UIColor, maximumWidth: CGFloat, outlineWidth: Double,
         loadImage: @escaping @MainActor (URL) async -> UIImage? = { await DanmakuStickerLoader.shared.image($0) }) {
        let height = ceil(font.lineHeight) + 10
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: height))
        clipsToBounds = true
        for span in spans.prefix(24) {
            let remaining = maximumWidth - bounds.width
            guard remaining > 14 else { break }
            switch span {
            case let .text(value):
                appendText(value, font: font, color: color, width: remaining, outlineWidth: outlineWidth)
            case let .image(url, fallback):
                let text = [fallback, "表情"].compactMap { $0 }.first { !$0.isEmpty } ?? "表情"
                guard DanmakuStickerURL.permits(url) else {
                    appendText(text, font: font, color: color, width: remaining, outlineWidth: outlineWidth)
                    continue
                }
                let label = appendText(text, font: font, color: color, width: remaining, outlineWidth: outlineWidth)
                let container = UIImageView(frame: label.frame.insetBy(dx: 1, dy: 2))
                container.contentMode = .scaleAspectFit
                addSubview(container)
                Task { [weak container, weak label] in
                    guard container?.superview?.superview != nil,
                          let image = await loadImage(url),
                          let container, container.superview?.superview != nil else { return }
                    container.image = image
                    label?.isHidden = true
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(spans:font:color:maximumWidth:outlineWidth:)") }

    @discardableResult
    private func appendText(_ text: String, font: UIFont, color: UIColor, width: CGFloat, outlineWidth: Double) -> DanmakuTextView {
        let label = DanmakuTextView(text, font: font, color: color, maximumWidth: width, outlineWidth: outlineWidth)
        label.frame.origin.x = bounds.width
        addSubview(label)
        bounds.size.width += label.bounds.width
        return label
    }
}
