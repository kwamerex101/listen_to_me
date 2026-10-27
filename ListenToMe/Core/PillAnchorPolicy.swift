import CoreGraphics

/// Geometry shared by restored positions and expanded floating controls.
enum PillAnchorPolicy {
    static func isVisible(_ anchor: CGPoint, on screens: [CGRect]) -> Bool {
        let idleChip = CGRect(x: anchor.x - 24, y: anchor.y - 6, width: 48, height: 12)
        return screens.contains { frame in
            let overlap = frame.intersection(idleChip)
            return overlap.width >= 24 && overlap.height >= 6
        }
    }

    /// The anchor is the bottom center of the visible chip. Keep its
    /// controls inside one screen, including when the saved idle position
    /// is near an edge. This never changes the saved preference.
    static func displayAnchor(_ anchor: CGPoint, visibleSize: CGSize, on screens: [CGRect]) -> CGPoint {
        guard let screen = screens.first(where: { $0.contains(anchor) }) ?? screens.min(by: {
            distanceSquared(anchor, $0) < distanceSquared(anchor, $1)
        }) else { return anchor }
        let margin: CGFloat = 8
        let minimumX = screen.minX + visibleSize.width / 2 + margin
        let maximumX = screen.maxX - visibleSize.width / 2 - margin
        let minimumY = screen.minY + margin
        let maximumY = screen.maxY - visibleSize.height - margin
        return CGPoint(
            x: minimumX <= maximumX ? min(max(anchor.x, minimumX), maximumX) : screen.midX,
            y: minimumY <= maximumY ? min(max(anchor.y, minimumY), maximumY) : screen.minY
        )
    }

    private static func distanceSquared(_ anchor: CGPoint, _ frame: CGRect) -> CGFloat {
        let x = anchor.x - frame.midX
        let y = anchor.y - frame.midY
        return x * x + y * y
    }
}
