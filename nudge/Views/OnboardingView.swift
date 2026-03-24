import SwiftUI

struct OnboardingView: View {
    @AppStorage("nudge.onboardingComplete") private var onboardingComplete = false
    @AppStorage("nudge.userName") private var userName = ""
    @AppStorage("nudge.userGoal") private var userGoal = ""

    @State private var step: OnboardingStep = .splash
    @State private var nameInput = ""
    @State private var selectedGoal: UserGoal? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            switch step {
            case .splash:
                splashScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            case .name:
                nameScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            case .goal:
                goalScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            case .notifications:
                notificationsScreen
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: step)
    }

    // MARK: - Step 1: Splash

    private var splashScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Logo + title
                VStack(spacing: 16) {
                    Text("🏃")
                        .font(.system(size: 72))

                    VStack(spacing: 8) {
                        Text("Nudge")
                            .font(.system(size: 42, weight: .bold, design: .rounded))

                        Text("Your personal movement coach")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Feature bullets
                VStack(alignment: .leading, spacing: 16) {
                    FeatureBullet(emoji: "📊", text: "Learns your patterns over time")
                    FeatureBullet(emoji: "✨", text: "AI nudges tailored to you")
                    FeatureBullet(emoji: "🔔", text: "Gentle daily reminders")
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                Haptics.impact(.medium)
                withAnimation(.easeInOut(duration: 0.35)) { step = .name }
            } label: {
                Text("Get started →")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 2: Name

    private var nameScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Text("👋")
                    .font(.system(size: 64))

                VStack(spacing: 10) {
                    Text("What should I call you?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("I'll use your name to make your daily nudges feel personal.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("Your name", text: $nameInput)
                    .font(.system(.title3, design: .rounded))
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .focused($nameFocused)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onSubmit { advanceFromName() }
            }
            .padding(.horizontal, 32)
            .onAppear { nameFocused = true }

            Spacer()

            Button {
                advanceFromName()
            } label: {
                Text("Continue →")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(nameInput.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.blue.opacity(0.3)
                                : Theme.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .disabled(nameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func advanceFromName() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.impact(.medium)
        userName = trimmed
        withAnimation(.easeInOut(duration: 0.35)) { step = .goal }
    }

    // MARK: - Step 3: Goal

    private var goalScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Text("🎯")
                    .font(.system(size: 64))

                VStack(spacing: 10) {
                    Text("What's your goal?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("I'll tailor your nudges and coaching to help you get there.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ForEach(UserGoal.allCases, id: \.rawValue) { goal in
                        Button {
                            Haptics.impact(.light)
                            selectedGoal = goal
                        } label: {
                            HStack(spacing: 14) {
                                Text(goal.emoji)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.title)
                                        .font(.system(.body, design: .rounded).weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(goal.subtitle)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedGoal == goal ? Theme.blue.opacity(0.08) : Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(selectedGoal == goal ? Theme.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                guard let goal = selectedGoal else { return }
                Haptics.impact(.medium)
                userGoal = goal.rawValue
                withAnimation(.easeInOut(duration: 0.35)) { step = .notifications }
            } label: {
                Text("Continue →")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(selectedGoal == nil ? Theme.blue.opacity(0.3) : Theme.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .disabled(selectedGoal == nil)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 4: Notifications

    private var notificationsScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Text("🔔")
                    .font(.system(size: 64))

                VStack(spacing: 10) {
                    Text("Stay on track")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Nudge sends a gentle evening reminder at 9pm to log your day, and a personalised morning message at 10am.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Permission preview
                VStack(alignment: .leading, spacing: 12) {
                    NotificationPreviewRow(time: "9:00 PM", text: "How'd movement go today?")
                    NotificationPreviewRow(time: "10:00 AM", text: "Your morning nudge is ready ✨")
                }
                .padding(16)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    Haptics.impact(.medium)
                    Task {
                        await NotificationService.requestPermission()
                        NotificationService.scheduleAll()
                        finishOnboarding()
                    }
                } label: {
                    Text("Allow Notifications")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                Button {
                    finishOnboarding()
                } label: {
                    Text("Skip for now")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func finishOnboarding() {
        onboardingComplete = true
    }
}

// MARK: - Supporting Views

private struct FeatureBullet: View {
    let emoji: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 36)
            Text(text)
                .font(.system(.body, design: .rounded))
            Spacer()
        }
    }
}

private struct NotificationPreviewRow: View {
    let time: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
            Spacer()
        }
    }
}

// MARK: - Step enum

private enum OnboardingStep {
    case splash
    case name
    case goal
    case notifications
}

#Preview {
    OnboardingView()
}
