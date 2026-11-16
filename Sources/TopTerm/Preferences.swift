import AppKit
import TopTermCore

final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["heightFraction": PanelGeometry.defaultFraction, "fontSize": 13.0])
    }

    var heightFraction: Double {
        get { PanelGeometry.savedFraction(defaults.double(forKey: "heightFraction")) }
        set { defaults.set(PanelGeometry.savedFraction(newValue), forKey: "heightFraction") }
    }

    var fontSize: CGFloat {
        get { min(28, max(10, defaults.double(forKey: "fontSize"))) }
        set { defaults.set(min(28, max(10, newValue)), forKey: "fontSize") }
    }

    var keyBinding: KeyBinding {
        get {
            guard let data = defaults.data(forKey: "showHideShortcut"),
                  let binding = try? JSONDecoder().decode(KeyBinding.self, from: data), binding.isValid else {
                return .defaultBinding
            }
            return binding
        }
        set {
            guard newValue.isValid, let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: "showHideShortcut")
        }
    }
}

enum Palette {
    static let background = NSColor(srgbRed: 0.055, green: 0.064, blue: 0.080, alpha: 1)
    static let chrome = NSColor(srgbRed: 0.085, green: 0.098, blue: 0.12, alpha: 1)
    static let accent = NSColor(srgbRed: 0.46, green: 0.85, blue: 0.72, alpha: 1)
    static let foreground = NSColor(srgbRed: 0.88, green: 0.91, blue: 0.94, alpha: 1)
}
