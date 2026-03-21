import SwiftUI

// MARK: - Carbon palette  (adaptive: light ↔ dark)
//
//  Light  Dark
//  Background  #F9F9F9  #0C0C0E
//  Card        #EFEFEF  #1C1C1F
//  Green       #16A34A  #22C55E  (move / positive)
//  Blue        #2563EB  #60A5FA  (CTA / interactive)
//  Muted       #9CA3AF  #4B5563  (rest / secondary accents)

enum Theme {
    static let background = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "0C0C0E") : UIColor(hex: "F9F9F9")
    })
    static let card = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "1C1C1F") : UIColor(hex: "EFEFEF")
    })
    static let green = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "22C55E") : UIColor(hex: "16A34A")
    })
    static let blue = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "60A5FA") : UIColor(hex: "2563EB")
    })
    static let purple = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "A78BFA") : UIColor(hex: "6366F1")
    })
    static let muted = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "4B5563") : UIColor(hex: "9CA3AF")
    })
}

// MARK: - UIColor hex (used by adaptive Theme colors above)

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, alpha: Double(a) / 255)
    }
}

// MARK: - SwiftUI Color hex convenience (for inline one-off colours in views)

extension Color {
    init(hex: String) {
        let uic = UIColor(hex: hex)
        self.init(uiColor: uic)
    }
}
