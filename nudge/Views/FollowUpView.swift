import SwiftUI
import SwiftData
import WidgetKit

struct FollowUpView: View {
    let didMove: Bool
    var preselectedTag: String? = nil
    var entryDate: Date = Date.now
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext

    private let defaultChips: [(emoji: String, label: String, tag: String)] = [
        ("🚶", "Walk", "walk"),
        ("🏃", "Run", "run"),
        ("😴", "Too tired", "tired"),
        ("💼", "Busy day", "busy")
    ]

    @State private var selectedTags: Set<String> = []
    @State private var note = ""
    @State private var isSaving = false
    @State private var showReaction = false
    @State private var reactionText: String? = nil
    @State private var showAddActivity = false
    private let contextChips: [(emoji: String, label: String, tag: String)] = [
        ("🤒", "Not feeling well", "sick"),
        ("🤕", "Injury / pain",    "injury"),
        ("✈️", "Traveling",        "travel"),
        ("💼", "Busy period",      "busy_life"),
        ("🎉", "Special day",      "special")
    ]
    @State private var contextTag: String? = nil
    @FocusState private var noteFocused: Bool

    var body: some View {
        ZStack {
          mainContent
          if showReaction {
              ReactionOverlayView(
                  didMove: didMove,
                  reactionText: reactionText,
                  onDismiss: onDone
              )
              .transition(.opacity)
          }
        }
        .animation(.easeInOut(duration: 0.25), value: showReaction)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(didMove ? "Nice! What did you do?" : "That's okay.")
                    .font(.title2.bold())
                Text("Fully optional — skip if you like.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 28)

            // Activity chips (default + custom + add button)
            FlowLayout(spacing: 10) {
                ForEach(defaultChips, id: \.tag) { chip in
                    ChipButton(
                        emoji: chip.emoji,
                        label: chip.label,
                        isSelected: selectedTags.contains(chip.tag)
                    ) {
                        Haptics.impact(.light)
                        toggleTag(chip.tag)
                    }
                }
                ForEach(ActivityStore.shared.activities) { chip in
                    ChipButton(
                        emoji: chip.emoji,
                        label: chip.label,
                        isSelected: selectedTags.contains(chip.id)
                    ) {
                        Haptics.impact(.light)
                        toggleTag(chip.id)
                    }
                }
                // Add new activity
                Button { showAddActivity = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("Add")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.card)
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .sheet(isPresented: $showAddActivity) {
                AddActivitySheet()
            }

            // Note field
            TextField("Add a note... (optional)", text: $note)
                .focused($noteFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.top, 20)

            // Life context (optional flag)
            VStack(alignment: .leading, spacing: 10) {
                Text("Any context?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 24)

                FlowLayout(spacing: 8) {
                    ForEach(contextChips, id: \.tag) { chip in
                        Button {
                            Haptics.impact(.light)
                            contextTag = contextTag == chip.tag ? nil : chip.tag
                        } label: {
                            HStack(spacing: 5) {
                                Text(chip.emoji)
                                Text(chip.label)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(contextTag == chip.tag ? Color.orange.opacity(0.12) : Theme.card)
                            .foregroundStyle(contextTag == chip.tag ? Color.orange : .secondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(contextTag == chip.tag ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: contextTag)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Skip") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.card)
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button("Save") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .onTapGesture { noteFocused = false }
        .onAppear {
            if let tag = preselectedTag { selectedTags.insert(tag) }
        }
        // newline sentinel — keep sheet attached to the right parent
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) { selectedTags.remove(tag) }
        else { selectedTags.insert(tag) }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        noteFocused = false
        Haptics.success()

        let entry = Entry(
            date: entryDate,
            didMove: didMove,
            activities: Array(selectedTags),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        modelContext.insert(entry)

        // Tell the widget today is logged so it switches to the result state
        SharedStore.todayCheckIn = CheckInRecord(didMove: didMove, date: entry.date)
        SharedStore.clearPendingCheckIn()
        WidgetCenter.shared.reloadAllTimelines()

        // Cancel tonight's follow-up reminder — user already logged
        NotificationService.cancelFollowUp()

        // Show reaction overlay — onDone() is called by its dismiss handler
        showReaction = true

        // Fetch reaction + HK stats + sync in parallel; onDone() fires via overlay dismiss
        let activities = Array(selectedTags)
        let entryDate = entry.date
        let capturedContextTag = contextTag
        let capturedContextChips = contextChips
        Task {
            async let reactionFetch = BackendService.fetchReaction(didMove: didMove, activities: activities)
            let stats = await HealthKitService.shared.fetchStats(for: entryDate)
            async let syncTask: () = BackendService.syncEntry(entry, stats: stats)

            if let text = try? await reactionFetch {
                await MainActor.run { reactionText = text }
            }
            try? await syncTask
            await MainActor.run { entry.synced = true }

            // Store life context memory if user flagged something
            if let tag = capturedContextTag,
               let chip = capturedContextChips.first(where: { $0.tag == tag }) {
                let dateStr = entryDate.formatted(date: .long, time: .omitted)
                let content = "[Life context on \(dateStr)] User flagged: \(chip.label). This may be relevant context for understanding movement patterns around this date."
                await BackendService.storeMemory(type: .context, content: content)
            }
        }
    }
}

// MARK: - Chip Button

struct ChipButton: View {
    let emoji: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.blue.opacity(0.15) : Theme.card)
            .foregroundStyle(isSelected ? Theme.blue : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Theme.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.view.sizeThatFits(.unspecified)
                item.view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row()
        var x: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !currentRow.items.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
                x = 0
            }
            currentRow.items.append(RowItem(view: view, size: size))
            currentRow.height = max(currentRow.height, size.height)
            x += size.width + spacing
        }
        if !currentRow.items.isEmpty { rows.append(currentRow) }
        return rows
    }

    struct Row {
        var items: [RowItem] = []
        var height: CGFloat = 0
    }
    struct RowItem {
        let view: LayoutSubview
        let size: CGSize
    }
}

// MARK: - Add Activity Sheet

struct AddActivitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var emoji = ""
    @State private var label = ""
    @FocusState private var labelFocused: Bool

    private var canAdd: Bool { !label.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("🏋️", text: $emoji)
                            .font(.title2)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)

                        Divider()

                        TextField("e.g. Gym, Swim, Yoga…", text: $label)
                            .focused($labelFocused)
                            .submitLabel(.done)
                            .onSubmit { if canAdd { commitAdd() } }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Activity name")
                } footer: {
                    Text("Type an emoji and a short name. Your new activity will appear in all check-in screens.")
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commitAdd() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canAdd ? Theme.blue : .secondary)
                        .disabled(!canAdd)
                }
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .onAppear { labelFocused = true }
    }

    private func commitAdd() {
        let e = emoji.trimmingCharacters(in: .whitespaces)
        let l = label.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return }
        ActivityStore.shared.add(emoji: e.isEmpty ? "⭐️" : e, label: l)
        Haptics.success()
        dismiss()
    }
}

#Preview {
    FollowUpView(didMove: true, onDone: {})
        .modelContainer(for: Entry.self, inMemory: true)
}
