import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [Entry]

    @AppStorage("nudge.userGoal") private var userGoal = ""

    private var profileSummarySnippet: String? {
        var parts: [String] = []
        if let s = UserProfile.sex { parts.append(s.title) }
        if let a = UserProfile.age { parts.append("\(a) yrs") }
        if let w = UserProfile.weightKg { parts.append(String(format: "%.0fkg", w)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @State private var showAddActivitySheet = false
    @State private var showUploadReport = false

    private var lastReportDate: String? {
        guard let iso = UserDefaults.standard.string(forKey: "nudge.lastReportDate"),
              let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // Reset local data state
    @State private var showResetConfirm = false
    @State private var isResetting = false
    @State private var resetDone = false

    // Delete Supermemory state
    @State private var showDeleteMemoryConfirm = false
    @State private var isDeletingMemory = false
    @State private var deleteMemoryResult: String? = nil
    @State private var deleteMemoryFailed = false

    // Notification time pickers
    @State private var eveningTime  = Self.minutesToDate(NotificationService.eveningMinutes)
    @State private var morningTime  = Self.minutesToDate(NotificationService.morningMinutes)
    @State private var followUpTime = Self.minutesToDate(NotificationService.followUpMinutes)

    #if DEBUG
    @State private var backendURL = UserDefaults.standard.string(forKey: "nudge.backendURL") ?? ""
    #endif

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Your goal section
                Section {
                    if let goal = UserGoal(rawValue: userGoal) {
                        Label("\(goal.emoji) \(goal.title)", systemImage: "target")
                    }
                    NavigationLink("Change goal") {
                        GoalPickerView(selectedGoal: Binding(
                            get: { UserGoal(rawValue: userGoal) },
                            set: { userGoal = $0?.rawValue ?? "" }
                        ))
                    }
                } header: {
                    Text("Your goal")
                }

                // MARK: - Profile section
                Section {
                    NavigationLink {
                        EditProfileView()
                    } label: {
                        HStack {
                            Label("Edit profile", systemImage: "person.circle")
                            Spacer()
                            if let summary = profileSummarySnippet, !summary.isEmpty {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Used to personalise calorie targets, protein goals, and AI suggestions.")
                }

                // MARK: - Custom activities section
                Section {
                    ForEach(ActivityStore.shared.activities) { activity in
                        HStack(spacing: 10) {
                            Text(activity.emoji).font(.title3)
                            Text(activity.label)
                        }
                    }
                    .onDelete { offsets in
                        ActivityStore.shared.delete(atOffsets: offsets)
                    }

                    Button {
                        showAddActivitySheet = true
                    } label: {
                        Label("Add activity", systemImage: "plus.circle")
                            .foregroundStyle(Theme.blue)
                    }
                } header: {
                    Text("Custom activities")
                } footer: {
                    Text("Appear alongside Walk, Run, Tired, and Busy when logging a check-in.")
                }
                .sheet(isPresented: $showAddActivitySheet) {
                    AddActivitySheet()
                }

                // MARK: - Health reports section
                Section {
                    if let date = lastReportDate {
                        HStack {
                            Label("Last uploaded", systemImage: "doc.text.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showUploadReport = true
                    } label: {
                        Label("Upload health report", systemImage: "doc.badge.plus")
                            .foregroundStyle(Theme.blue)
                    }
                } header: {
                    Text("Health reports")
                } footer: {
                    Text("Upload blood tests or lab reports. Biomarkers are extracted and saved to your Coach memory for personalised insights.")
                }
                .sheet(isPresented: $showUploadReport) {
                    UploadReportView()
                }

                // MARK: - Info section
                Section {
                    HStack {
                        Label("User ID", systemImage: "person.circle")
                        Spacer()
                        Text(UserService.userId.prefix(8) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Local entries", systemImage: "calendar")
                        Spacer()
                        Text("\(entries.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Account")
                }

                // MARK: - Notification times
                Section {
                    DatePicker(
                        "Evening check-in",
                        selection: $eveningTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: eveningTime) { _, newVal in
                        NotificationService.setEvening(Self.dateToMinutes(newVal))
                    }

                    DatePicker(
                        "Morning nudge",
                        selection: $morningTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: morningTime) { _, newVal in
                        NotificationService.setMorning(Self.dateToMinutes(newVal))
                    }

                    DatePicker(
                        "Follow-up reminder",
                        selection: $followUpTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: followUpTime) { _, newVal in
                        NotificationService.setFollowUp(Self.dateToMinutes(newVal))
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("The follow-up reminder only fires on days you haven't logged yet.")
                }

                // MARK: - Reset local data
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        HStack {
                            if isResetting {
                                ProgressView()
                                    .padding(.trailing, 6)
                            } else if resetDone {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            Text(isResetting ? "Resetting…" : resetDone ? "Reset complete" : "Reset local data")
                        }
                    }
                    .disabled(isResetting)
                } header: {
                    Text("Local data")
                } footer: {
                    Text("Clears your check-in history on this device and generates a new user ID. Your AI memory in Supermemory is not affected.")
                }
                .confirmationDialog(
                    "Reset local data?",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) { performLocalReset() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete all \(entries.count) check-in entries on this device and assign you a new user ID. This cannot be undone.")
                }

                // MARK: - Delete Supermemory data
                Section {
                    Button(role: .destructive) {
                        showDeleteMemoryConfirm = true
                    } label: {
                        HStack {
                            if isDeletingMemory {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Deleting from Supermemory…")
                            } else {
                                Image(systemName: "brain.slash")
                                Text("Delete AI memory")
                            }
                        }
                    }
                    .disabled(isDeletingMemory)

                    if let result = deleteMemoryResult {
                        HStack(spacing: 6) {
                            Image(systemName: deleteMemoryFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(deleteMemoryFailed ? .orange : .green)
                            Text(result)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("AI memory")
                } footer: {
                    Text("Permanently removes everything stored about you in Supermemory. The morning nudge will become generic until you log new entries.")
                }
                .confirmationDialog(
                    "Delete AI memory?",
                    isPresented: $showDeleteMemoryConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete forever", role: .destructive) { performDeleteMemory() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes all your movement history from Supermemory. Your morning nudge will be generic until you build up new history. This cannot be undone.")
                }

                // MARK: - Debug: Backend URL override
                #if DEBUG
                Section {
                    TextField("https://…", text: $backendURL)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .onSubmit {
                            let trimmed = backendURL.trimmingCharacters(in: .whitespaces)
                            if trimmed.isEmpty {
                                UserDefaults.standard.removeObject(forKey: "nudge.backendURL")
                            } else {
                                UserDefaults.standard.set(trimmed, forKey: "nudge.backendURL")
                            }
                        }
                } header: {
                    Text("Backend URL (Debug)")
                } footer: {
                    Text("Leave empty to use the Railway production server. This section is only visible in Debug builds.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Time conversion helpers

    private static func minutesToDate(_ minutes: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date.now)
        comps.hour   = minutes / 60
        comps.minute = minutes % 60
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date.now
    }

    private static func dateToMinutes(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Actions

    private func performLocalReset() {
        isResetting = true
        // 1. Delete all SwiftData entries
        for entry in entries {
            modelContext.delete(entry)
        }
        // 2. Clear cached nudge
        UserDefaults.standard.removeObject(forKey: "nudge.morningNudgeText")
        UserDefaults.standard.removeObject(forKey: "nudge.morningNudgeDate")
        // 3. Delete Keychain UUID (new one generated on next access)
        UserService.deleteFromKeychain()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isResetting = false
            resetDone = true
        }
    }

    private func performDeleteMemory() {
        isDeletingMemory = true
        deleteMemoryResult = nil
        deleteMemoryFailed = false

        Task {
            do {
                let (deleted, failed) = try await BackendService.deleteSupermemoryData()
                await MainActor.run {
                    isDeletingMemory = false
                    deleteMemoryFailed = failed > 0
                    if failed == 0 {
                        deleteMemoryResult = "Deleted \(deleted) \(deleted == 1 ? "entry" : "entries") from Supermemory."
                    } else {
                        deleteMemoryResult = "Deleted \(deleted), couldn't remove \(failed). Try again."
                    }
                }
            } catch {
                await MainActor.run {
                    isDeletingMemory = false
                    deleteMemoryFailed = true
                    deleteMemoryResult = "Couldn't reach the server. Check it's running."
                }
            }
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSex      = UserProfile.sex
    @State private var ageText          = UserProfile.age.map { String($0) } ?? ""
    @State private var heightText       = UserProfile.heightCm.map { String(format: "%.0f", $0) } ?? ""
    @State private var weightText       = UserProfile.weightKg.map { String(format: "%.1f", $0) } ?? ""
    @State private var selectedActivity = UserProfile.activityLevel

    var body: some View {
        List {
            // Sex
            Section("Biological sex") {
                HStack(spacing: 10) {
                    ForEach(UserSex.allCases, id: \.rawValue) { s in
                        Button {
                            selectedSex = s
                            UserDefaults.standard.set(s.rawValue, forKey: "nudge.sex")
                        } label: {
                            Text(s.title)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedSex == s ? Theme.blue.opacity(0.1) : Theme.card)
                                .foregroundStyle(selectedSex == s ? Theme.blue : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(selectedSex == s ? Theme.blue : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            // Body stats
            Section("Body stats") {
                HStack {
                    Text("Age")
                    Spacer()
                    TextField("28", text: $ageText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: ageText) { _, v in
                            if let a = Int(v), a > 0 { UserDefaults.standard.set(a, forKey: "nudge.age") }
                        }
                    Text("yrs").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("175", text: $heightText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: heightText) { _, v in
                            if let h = Double(v), h > 0 { UserDefaults.standard.set(h, forKey: "nudge.heightCm") }
                        }
                    Text("cm").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("78", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: weightText) { _, v in
                            if let w = Double(v), w > 0 { UserDefaults.standard.set(w, forKey: "nudge.weightKg") }
                        }
                    Text("kg").foregroundStyle(.secondary)
                }
            }

            // Activity level
            Section("Lifestyle activity") {
                ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                    Button {
                        selectedActivity = level
                        UserDefaults.standard.set(level.rawValue, forKey: "nudge.activityLevel")
                    } label: {
                        HStack(spacing: 12) {
                            Text(level.emoji)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title).font(.body).foregroundStyle(.primary)
                                Text(level.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedActivity == level {
                                Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Computed targets (read-only preview)
            if UserProfile.bmi != nil || UserProfile.tdee != nil {
                Section("Estimated targets") {
                    if let bmi = UserProfile.bmi {
                        HStack {
                            Text("BMI")
                            Spacer()
                            Text(String(format: "%.1f", bmi))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let tdee = UserProfile.tdee {
                        HStack {
                            Text("Daily calorie need")
                            Spacer()
                            Text(String(format: "%.0f kcal", tdee))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let protein = UserProfile.proteinTargetG {
                        HStack {
                            Text("Protein target")
                            Spacer()
                            Text("\(protein)g / day")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onDisappear {
            Task { await UserProfile.syncToSupermemoryIfChanged() }
        }
        .navigationTitle("Your profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GoalPickerView: View {
    @Binding var selectedGoal: UserGoal?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(UserGoal.allCases, id: \.rawValue) { goal in
                Button {
                    selectedGoal = goal
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text(goal.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Text(goal.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedGoal == goal {
                            Image(systemName: "checkmark").foregroundStyle(Theme.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Change goal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: Entry.self, inMemory: true)
}
