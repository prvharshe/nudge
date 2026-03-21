import SwiftUI

struct CheckInView: View {
    let onAnswer: (Bool) -> Void

    @AppStorage("nudge.userName") private var userName = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── Question floats in the sky portion (top ~52%) ──────────────
                VStack(spacing: 16) {
                    Spacer(minLength: 20)

                    // Date badge
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .tracking(0.3)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())

                    VStack(spacing: 10) {
                        if !userName.isEmpty {
                            Text("Hey \(userName) 👋")
                                .font(.system(.title3, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary.opacity(0.75))
                        }

                        Text("Did you move\ntoday?")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .foregroundStyle(.primary)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 32)
                // Cap this section to ~52% of screen height so runners stay visible
                .frame(height: geo.size.height * 0.52)

                // ── Road + grass visible here (runners run through) ────────────
                Spacer()

                // ── Buttons float in the lower grass portion ───────────────────
                VStack(spacing: 12) {
                    // YES — tall hero button (green-tinted frosted glass)
                    Button {
                        Haptics.impact(.medium)
                        onAnswer(true)
                    } label: {
                        VStack(spacing: 12) {
                            Text("🙌").font(.system(size: 44))
                            Text("Yes, I moved")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .background {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Theme.green.opacity(colorScheme == .dark ? 0.22 : 0.12))
                        }
                        .foregroundStyle(colorScheme == .dark
                                         ? Color(hex: "52D990")
                                         : Theme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Theme.green.opacity(colorScheme == .dark ? 0.40 : 0.25),
                                        lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)

                    // NOT TODAY — shorter secondary
                    Button {
                        Haptics.impact(.medium)
                        onAnswer(false)
                    } label: {
                        HStack(spacing: 10) {
                            Text("😴").font(.title2)
                            Text("Not today")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

#Preview {
    CheckInView(onAnswer: { _ in })
}
