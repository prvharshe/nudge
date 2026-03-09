import SwiftUI
import SwiftData

struct FollowUpView: View {
    let didMove: Bool
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext

    private let chips: [(emoji: String, label: String, tag: String)] = [
        ("🚶", "Walk", "walk"),
        ("🏃", "Run", "run"),
        ("😴", "Too tired", "tired"),
        ("💼", "Busy day", "busy")
    ]

    @State private var selectedTags: Set<String> = []
    @State private var note = ""
    @State private var isSaving = false
    @FocusState private var noteFocused: Bool

    var body: some View {
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

            // Activity chips
            FlowLayout(spacing: 10) {
                ForEach(chips, id: \.tag) { chip in
                    ChipButton(
                        emoji: chip.emoji,
                        label: chip.label,
                        isSelected: selectedTags.contains(chip.tag)
                    ) {
                        if selectedTags.contains(chip.tag) {
                            selectedTags.remove(chip.tag)
                        } else {
                            selectedTags.insert(chip.tag)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            // Note field
            TextField("Add a note... (optional)", text: $note)
                .focused($noteFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button("Skip") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.systemGray6))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button("Save") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onTapGesture { noteFocused = false }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        noteFocused = false

        let entry = Entry(
            date: Date.now,
            didMove: didMove,
            activities: Array(selectedTags),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        modelContext.insert(entry)

        // Tell the widget today is logged so it switches to the result state
        SharedStore.todayCheckIn = CheckInRecord(didMove: didMove, date: entry.date)
        SharedStore.clearPendingCheckIn()

        Task {
            try? await BackendService.syncEntry(entry)
            await MainActor.run {
                entry.synced = true
                onDone()
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
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
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

#Preview {
    FollowUpView(didMove: true, onDone: {})
        .modelContainer(for: Entry.self, inMemory: true)
}
