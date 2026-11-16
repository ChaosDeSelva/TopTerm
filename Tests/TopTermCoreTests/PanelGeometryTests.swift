import CoreGraphics
import TopTermCore

@main
struct PanelGeometryChecks {
    static func main() {
        defaultUsesTopHalf()
        expansionDoesNotChangeSavedSize()
        dragOnScreenWithOffset()
        invalidPreferencesAndSmallDisplay()
        print("PASS: all four panel geometry checks")
    }

    static func expect(_ condition: Bool, _ name: String) {
        guard condition else { fatalError("FAIL: \(name)") }
    }

    static func defaultUsesTopHalf() {
        let screen = CGRect(x: 0, y: 80, width: 1512, height: 870)
        let frame = PanelGeometry.frame(in: screen, fraction: PanelGeometry.defaultFraction, expanded: false)
        expect(frame.width == screen.width, "full width")
        expect(frame.height == 435, "50 percent height")
        expect(frame.maxY == screen.maxY, "top anchor")
    }

    static func expansionDoesNotChangeSavedSize() {
        let screen = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        expect(PanelGeometry.frame(in: screen, fraction: 0.42, expanded: true) == screen, "expanded frame")
        let restored = PanelGeometry.frame(in: screen, fraction: 0.42, expanded: false)
        expect(restored.height == 454, "saved height restored")
        expect(restored.minX == -1920, "secondary display origin")
        expect(restored.maxY == screen.maxY, "secondary display top anchor")
    }

    static func dragOnScreenWithOffset() {
        let screen = CGRect(x: 1512, y: 200, width: 1920, height: 1000)
        expect(PanelGeometry.fraction(forBottomEdge: 800, in: screen) == 0.4, "drag coordinate")
        expect(PanelGeometry.fraction(forBottomEdge: 1500, in: screen) == 0.15, "minimum height")
        expect(PanelGeometry.fraction(forBottomEdge: -200, in: screen) == 0.95, "maximum saved height")
    }

    static func invalidPreferencesAndSmallDisplay() {
        expect(PanelGeometry.savedFraction(.nan) == 0.5, "invalid preference fallback")
        expect(PanelGeometry.savedFraction(.infinity) == 0.5, "infinite preference fallback")
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 120)
        expect(PanelGeometry.frame(in: tiny, fraction: 0.3, expanded: false) == tiny, "small display")
    }
}
