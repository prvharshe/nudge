import SwiftUI

struct OnboardingView: View {
    @AppStorage("nudge.onboardingComplete") private var onboardingComplete = false
    @AppStorage("nudge.userName") private var userName = ""
    @AppStorage("nudge.userGoal") private var userGoal = ""

    @State private var step: OnboardingStep = .splash
    @State private var nameInput = ""
    @State private var selectedGoal: UserGoal? = nil
    @FocusState private var nameFocused: Bool

    // Profile step
    @State private var selectedSex: UserSex? = nil
    @State private var ageInput    = ""
    @State private var heightInput = ""
    @State private var weightInput = ""
    @State private var selectedActivity: ActivityLevel? = nil

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
            case .profile:
                profileScreen
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
                withAnimation(.easeInOut(duration: 0.35)) { step = .profile }
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

    // MARK: - Step 4: Profile

    private var profileScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer().frame(height: 32)

                VStack(spacing: 26) {
                    // Header
                    VStack(spacing: 12) {
                        Text("👤")
                            .font(.system(size: 60))
                        VStack(spacing: 8) {
                            Text("A bit about you")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("Helps me give accurate calorie, protein, and nutrition targets.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    // Biological sex
                    VStack(alignment: .leading, spacing: 8) {
                        ProfileSectionLabel("Biological sex")
                        HStack(spacing: 8) {
                            ForEach(UserSex.allCases, id: \.rawValue) { s in
                                Button {
                                    Haptics.impact(.light)
                                    selectedSex = s
                                } label: {
                                    Text(s.title)
                                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedSex == s
                                                    ? Theme.blue.opacity(0.1) : Theme.card)
                                        .foregroundStyle(selectedSex == s ? Theme.blue : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(selectedSex == s
                                                              ? Theme.blue : Color.clear,
                                                              lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Age / Height / Weight row
                    VStack(alignment: .leading, spacing: 8) {
                        ProfileSectionLabel("Body stats")
                        HStack(spacing: 10) {
                            ProfileField(label: "Age",    placeholder: "28",  unit: "yrs", text: $ageInput,    keyboard: .numberPad)
                            ProfileField(label: "Height", placeholder: "175", unit: "cm",  text: $heightInput, keyboard: .numberPad)
                            ProfileField(label: "Weight", placeholder: "78",  unit: "kg",  text: $weightInput, keyboard: .decimalPad)
                        }
                    }

                    // Activity level
                    VStack(alignment: .leading, spacing: 8) {
                        ProfileSectionLabel("Lifestyle activity")
                        VStack(spacing: 8) {
                            ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                                Button {
                                    Haptics.impact(.light)
                                    selectedActivity = level
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(level.emoji).font(.title3)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(level.title)
                                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text(level.subtitle)
                                                .font(.system(.caption, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedActivity == level {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Theme.blue)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(selectedActivity == level
                                                ? Theme.blue.opacity(0.08) : Theme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(selectedActivity == level
                                                          ? Theme.blue : Color.clear,
                                                          lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 32)

                VStack(spacing: 12) {
                    Button {
                        saveProfile()
                        Haptics.impact(.medium)
                        withAnimation(.easeInOut(duration: 0.35)) { step = .notifications }
                    } label: {
                        Text("Continue →")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Theme.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { step = .notifications }
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
    }

    private func saveProfile() {
        if let s = selectedSex {
            UserDefaults.standard.set(s.rawValue, forKey: "nudge.sex")
        }
        if let a = Int(ageInput.trimmingCharacters(in: .whitespaces)), a > 0 {
            UserDefaults.standard.set(a, forKey: "nudge.age")
        }
        if let h = Double(heightInput.trimmingCharacters(in: .whitespaces)), h > 0 {
            UserDefaults.standard.set(h, forKey: "nudge.heightCm")
        }
        if let w = Double(weightInput.trimmingCharacters(in: .whitespaces)), w > 0 {
            UserDefaults.standard.set(w, forKey: "nudge.weightKg")
        }
        if let al = selectedActivity {
            UserDefaults.standard.set(al.rawValue, forKey: "nudge.activityLevel")
        }
    }

    // MARK: - Step 5: Notifications

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

// MARK: - Profile helper views

private struct ProfileSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

private struct ProfileField: View {
    let label: String
    let placeholder: String
    let unit: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            HStack(spacing: 3) {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step enum

private enum OnboardingStep {
    case splash
    case name
    case goal
    case profile
    case notifications
}

#Preview {
    OnboardingView()
}
