import CoreGraphics

enum MultiRoomGeometry {
    static func frames(count: Int, size: CGSize, layout: MultiRoomLayout, primaryIndex: Int) -> [CGRect] {
        guard (MultiRoomSelection.minimum...MultiRoomSelection.maximum).contains(count) else { return [] }
        let gap: CGFloat = 12
        let bounds = CGRect(origin: .zero, size: size)
        switch layout {
        case .grid:
            let rows = count == 2 ? 1 : 2
            let width = max(0, (size.width - gap) / 2)
            let height = max(0, (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
            return (0..<count).map { index in
                fitted(in: CGRect(x: CGFloat(index % 2) * (width + gap), y: CGFloat(index / 2) * (height + gap),
                                  width: width, height: height))
            }
        case .primary:
            let available = max(0, size.width - gap)
            let width = available / 3
            let primary = CGRect(x: 0, y: 0, width: available - width, height: size.height)
            let secondary = count - 1
            let height = min(width * 9 / 16, max(0, (size.height - CGFloat(secondary - 1) * gap) / CGFloat(secondary)))
            let top = (size.height - CGFloat(secondary) * height - CGFloat(secondary - 1) * gap) / 2
            var slots = (0..<secondary).map { index in
                fitted(in: CGRect(x: bounds.maxX - width, y: top + CGFloat(index) * (height + gap), width: width, height: height))
            }
            slots.insert(fitted(in: primary), at: min(max(0, primaryIndex), secondary))
            return slots
        }
    }

    static func fitted(in bounds: CGRect) -> CGRect {
        let width = min(bounds.width, bounds.height * 16 / 9)
        let height = width * 9 / 16
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }
}
