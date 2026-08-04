import SwiftUI

struct CoachKeepsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let keepStore: CoachKeepStore
    var highlightedKeepID: UUID? = nil
    var onAskFollowUp: (CoachKeep) -> Void

    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if keepStore.keeps.isEmpty {
                    ContentUnavailableView(
                        "No keeps yet",
                        systemImage: "bookmark",
                        description: Text("Long-press a coach reply and choose Keep this to save advice Coach will remember.")
                    )
                } else {
                    List {
                        ForEach(keepStore.keeps) { keep in
                            keepCard(keep)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: deleteKeeps)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AmbientBackground())
            .navigationTitle("Your keeps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let highlightedKeepID {
                    expandedIDs.insert(highlightedKeepID)
                }
            }
        }
    }

    @ViewBuilder
    private func keepCard(_ keep: CoachKeep) -> some View {
        let isExpanded = expandedIDs.contains(keep.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(keep.label)
                        .font(.subheadline.weight(.semibold))

                    Text(keep.savedAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.brandGradient)
            }

            Text("You asked")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(keep.question)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if isExpanded {
                Text("Coach said")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(keep.answer)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(keep.answer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Button(isExpanded ? "Show less" : "Read full") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedIDs.remove(keep.id)
                        } else {
                            expandedIDs.insert(keep.id)
                        }
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.brandCoral)

                Spacer()

                Button {
                    dismiss()
                    onAskFollowUp(keep)
                } label: {
                    Label("Ask follow-up", systemImage: "arrow.up.forward")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Theme.brandCoral)
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func deleteKeeps(at offsets: IndexSet) {
        let ids = offsets.map { keepStore.keeps[$0].id }
        for id in ids {
            keepStore.unkeep(id: id)
        }
    }
}
