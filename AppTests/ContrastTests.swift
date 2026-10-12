@testable import EarReader
import Testing
import UIKit

/// WCAG 2.x AA (4.5:1) for every text/background pair, light and dark.
struct ContrastTests {
    static let pairs: [(text: String, background: String)] = [
        ("textPrimary", "background"), ("textPrimary", "surface"), ("textPrimary", "surfaceSecondary"),
        ("textSecondary", "background"), ("textSecondary", "surface"), ("textSecondary", "surfaceSecondary"),
        ("primary", "background"), ("primary", "surface"),
        ("accent", "background"), ("accent", "surface"),
        ("onPrimary", "primary"), ("onPrimary", "primaryPressed"),
    ]

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `text pairs meet AA`(style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        for (text, background) in Self.pairs {
            let fg = try #require(UIColor(named: text, in: .main, compatibleWith: traits), "missing \(text)")
            let bg = try #require(UIColor(named: background, in: .main, compatibleWith: traits), "missing \(background)")
            let ratio = Self.contrast(fg.resolvedColor(with: traits), bg.resolvedColor(with: traits))
            #expect(ratio >= 4.5, "\(text) on \(background) (\(style == .dark ? "dark" : "light")): \(ratio)")
        }
    }

    static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    static func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    @Test func `luminance math`() {
        #expect(abs(Self.contrast(.black, .white) - 21) < 0.01)
    }
}
