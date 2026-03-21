import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [Entry]

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

#Preview {
    SettingsView()
        .modelContainer(for: Entry.self, inMemory: true)
}
