import Combine
import CoreText
import SimpleLiveTVOSCore
import SwiftUI
import UIKit

struct DanmakuOverlay: UIViewRepresentable {
    let events: PassthroughSubject<DanmakuEvent, Never>

    func makeUIView(context: Context) -> DanmakuSurface {
        let surface = DanmakuSurface(frame: .zero)
        surface.subscription = events.sink { [weak surface] event in
            surface?.display(event)
        }
        return surface
    }

    func updateUIView(_ uiView: DanmakuSurface, context: Context) {}

    static func dismantleUIView(_ uiView: DanmakuSurface, coordinator: Void) {
        uiView.subscription = nil
        uiView.clear()
    }
}

final class DanmakuSurface: UIView {
    private let font = UIFont.systemFont(ofSize: 36, weight: .semibold)
    private let horizontalGap: CGFloat = 40
    private let topInset: CGFloat = 12
    private var surfaceSize = CGSize.zero
    private var laneReadyTimes: [CFTimeInterval] = []
    var subscription: AnyCancellable?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private var lineHeight: CGFloat { ceil(font.lineHeight) + 10 }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != surfaceSize else { return }
        surfaceSize = bounds.size
        clear()
        let laneCount = max(0, Int((bounds.height * 0.25 - topInset) / lineHeight))
        laneReadyTimes = Array(repeating: 0, count: laneCount)
    }

    func display(_ event: DanmakuEvent, now: CFTimeInterval = CACurrentMediaTime()) {
        guard bounds.width > 0,
              let lane = laneReadyTimes.firstIndex(where: { $0 <= now }) else { return }
        let message = event.message.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }

        let color = event.color
        let foreground = UIColor(red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                                 blue: CGFloat(color.blue) / 255, alpha: 1)
        let label = DanmakuTextView(message, font: font, color: foreground, maximumWidth: bounds.width)
        let width = label.bounds.width
        let speed = bounds.width / 9
        // With one velocity for all text, the previous tail only needs to clear the entry plus the gap.
        laneReadyTimes[lane] = now + (width + horizontalGap) / speed
        label.frame = CGRect(x: bounds.maxX, y: topInset + CGFloat(lane) * lineHeight, width: width, height: lineHeight)
        addSubview(label)

        UIView.animate(withDuration: (bounds.width + width) / speed, delay: 0, options: .curveLinear) {
            label.frame.origin.x = -width
        } completion: { [weak label] _ in
            label?.removeFromSuperview()
        }
    }

    func clear() {
        for label in subviews {
            label.layer.removeAllAnimations()
            label.removeFromSuperview()
        }
        laneReadyTimes = Array(repeating: 0, count: laneReadyTimes.count)
    }
}

final class DanmakuTextView: UIView {
    private static let horizontalInset: CGFloat = 5
    private let fill: CTLine
    private let outline: CTLine

    init(_ message: String, font: UIFont, color: UIColor, maximumWidth: CGFloat) {
        let contentWidth = max(0, maximumWidth - Self.horizontalInset * 2)
        let fill = Self.line(message, attributes: [.font: font, .foregroundColor: color], width: contentWidth)
        self.fill = fill
        // Repaint the solid glyphs over the stroke so it cannot eat into small strokes and counters.
        outline = Self.line(message, attributes: [
            .font: font,
            .foregroundColor: UIColor.black,
            .strokeColor: UIColor.black,
            .strokeWidth: -8,
        ], width: contentWidth)
        let width = min(maximumWidth, ceil(CTLineGetTypographicBounds(fill, nil, nil, nil)) + Self.horizontalInset * 2)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: ceil(font.lineHeight) + 10))
        isOpaque = false
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(_:font:color:maximumWidth:)") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        CTLineGetTypographicBounds(fill, &ascent, &descent, nil)

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: Self.horizontalInset, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.setLineJoin(.round)
        let baseline = (bounds.height - ascent + descent) / 2
        for line in [outline, fill] {
            context.saveGState()
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 0, y: baseline)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private static func line(_ message: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CTLine {
        let text = CTLineCreateWithAttributedString(NSAttributedString(string: message, attributes: attributes))
        guard CTLineGetTypographicBounds(text, nil, nil, nil) > width else { return text }
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(text, width, .end, ellipsis) ?? ellipsis
    }
}
