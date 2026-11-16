import Foundation
import CoreGraphics

public struct PanelGeometry {
    public static let defaultFraction = 0.50

    public static func savedFraction(_ value: Double) -> Double {
        guard value.isFinite else { return defaultFraction }
        return min(0.95, max(0.15, value))
    }

    public static func frame(in visibleFrame: CGRect, fraction: Double, expanded: Bool) -> CGRect {
        let height = (expanded ? visibleFrame.height :
            min(visibleFrame.height, max(160, visibleFrame.height * savedFraction(fraction)))).rounded()
        return CGRect(x: visibleFrame.minX, y: visibleFrame.maxY - height,
                      width: visibleFrame.width, height: height)
    }

    public static func fraction(forBottomEdge y: Double, in visibleFrame: CGRect) -> Double {
        guard visibleFrame.height > 0 else { return defaultFraction }
        return savedFraction((visibleFrame.maxY - y) / visibleFrame.height)
    }
}
