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

    static let ink = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "07111F") : UIColor(hex: "F7F3EE")
    })
    static let surface = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "111B2D").withAlphaComponent(0.82) : UIColor.white.withAlphaComponent(0.72)
    })
    static let elevatedSurface = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "172238") : UIColor(hex: "FFFDFC")
    })
    static let glassSurface = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "1A2740").withAlphaComponent(0.62) : UIColor.white.withAlphaComponent(0.58)
    })
    static let hairline = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "FFF4E3").withAlphaComponent(0.13) : UIColor(hex: "182A4A").withAlphaComponent(0.09)
    })
    static let warmGlow = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "FF9637").withAlphaComponent(0.18) : UIColor(hex: "E78A78").withAlphaComponent(0.16)
    })
    static let secondaryText = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "A8B3C7") : UIColor(hex: "667085")
    })

    static let brandNavy = Color(hex: "182A4A")
    static let brandCoral = Color(hex: "E78A78")
    static let brandAmber = Color(hex: "FF9637")
    static let brandCream = Color(hex: "FFF4E3")

    static let brandGradient = LinearGradient(
        colors: [brandNavy, brandCoral, brandAmber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandGradientSoft = LinearGradient(
        colors: [
            brandNavy.opacity(0.12),
            brandCoral.opacity(0.10),
            brandAmber.opacity(0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandBorderGradient = LinearGradient(
        colors: [
            brandCream.opacity(0.7),
            brandCoral.opacity(0.55),
            brandAmber.opacity(0.65)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Brand surfaces

extension View {
    func brandPrimaryButton(isEnabled: Bool = true, cornerRadius: CGFloat = 20) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.blue.opacity(0.3)))
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func brandSelectedSurface(isSelected: Bool, cornerRadius: CGFloat = 12) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.brandGradientSoft) : AnyShapeStyle(Theme.card))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(Theme.brandBorderGradient) : AnyShapeStyle(Color.clear),
                                  lineWidth: isSelected ? 1.5 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func surfaceCard(cornerRadius: CGFloat = 20, borderOpacity: Double = 1) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.glassSurface)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(borderOpacity), lineWidth: 1)
            }
    }

    func nocturnePrimaryButton(isEnabled: Bool = true, cornerRadius: CGFloat = 18) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.muted.opacity(0.28)))
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: isEnabled ? Theme.warmGlow : .clear, radius: 14, y: 6)
    }

    func nocturneSecondaryButton(cornerRadius: CGFloat = 18) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.glassSurface)
            }
            .foregroundStyle(Theme.secondaryText)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Nocturne system views

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.ink

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(hex: "07111F"),
                        Color(hex: "101B31"),
                        Theme.brandNavy.opacity(0.92),
                        Theme.brandCoral.opacity(0.26),
                        Theme.brandAmber.opacity(0.20)
                    ]
                    : [
                        Color(hex: "FFFDFC"),
                        Color(hex: "F8F2EC"),
                        Theme.brandCream.opacity(0.86),
                        Theme.brandCoral.opacity(0.18),
                        Theme.brandAmber.opacity(0.16)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [
                        Color.clear,
                        Theme.brandCoral.opacity(colorScheme == .dark ? 0.16 : 0.10),
                        Theme.brandAmber.opacity(colorScheme == .dark ? 0.22 : 0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxHeight: 260)
            }
        }
        .ignoresSafeArea()
    }
}

struct GradientIconBadge: View {
    let systemName: String
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.brandGradientSoft)
            Circle()
                .strokeBorder(Theme.brandBorderGradient, lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)
        }
        .frame(width: size, height: size)
    }
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
