import SwiftUI

struct CheckInView: View {
    let onAnswer: (Bool, String?) -> Void   // didMove + optional pre-selected tag

    @AppStorage("nudge.userName") private var userName = ""
    @Environment(\.colorScheme) private var colorScheme

    @State private var detection: HealthDetection? = nil
    @State private var isDetecting = true
    @State private var liveSteps: Int? = nil

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── Question (top ~52% — sky portion) ─────────────────────────
                VStack(spacing: 16) {
                    Spacer(minLength: 20)

                    HStack(spacing: 8) {
                        Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .tracking(0.3)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())

                        if let steps = liveSteps, steps > 0 {
                            Text("\(steps.formatted()) steps")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                                .transition(.opacity.combined(with: .scale))
                        }
                    }

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
                .frame(height: geo.size.height * 0.52)

                Spacer()

                // ── HealthKit detection banner ─────────────────────────────────
                if let d = detection, d.didMove {
                    healthKitBanner(d)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── YES / NOT TODAY buttons ────────────────────────────────────
                VStack(spacing: 12) {
                    Button {
                        Haptics.impact(.medium)
                        onAnswer(true, detection?.activityTag)
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
                        .foregroundStyle(colorScheme == .dark ? Color(hex: "22C55E") : Theme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Theme.green.opacity(colorScheme == .dark ? 0.40 : 0.25),
                                        lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.impact(.medium)
                        onAnswer(false, nil)
                    } label: {
                        HStack(spacing: 10) {
                            Text("😴").font(.title2)
                            Text("Not today")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(.ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
        .task { await runDetection() }
        .animation(.spring(duration: 0.4), value: detection != nil)
    }

    // MARK: - HealthKit banner

    @ViewBuilder
    private func healthKitBanner(_ d: HealthDetection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.green)

            VStack(alignment: .leading, spacing: 1) {
                Text("Apple Health: \(d.summary)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Tap YES to log it instantly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Quick-log shortcut
            Button {
                Haptics.impact(.medium)
                onAnswer(true, d.activityTag)
            } label: {
                Text("Log it")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Detection

    private func runDetection() async {
        let granted = await HealthKitService.shared.requestAuthorization()
        guard granted else { isDetecting = false; return }
        async let detectionTask = HealthKitService.shared.detectToday()
        async let stepsTask = HealthKitService.shared.fetchStats(for: .now)
        detection = await detectionTask
        let steps = await stepsTask?.steps ?? 0
        if steps > 0 { liveSteps = steps }
        isDetecting = false
    }
}

#Preview {
    CheckInView(onAnswer: { _, _ in })
}
