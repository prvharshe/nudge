import SwiftUI

// MARK: - Metric Info Sheet

struct MetricInfoSheet: View {
    let info: MetricInfo
    let currentValue: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── Header: icon + title + personalised sentence ──────────
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: info.icon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(info.iconColor)
                            .frame(width: 50, height: 50)
                            .background(info.iconColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text(info.title)
                                .font(.title3.bold())

                            if let insight = info.userInsight?(currentValue) {
                                Text(insight)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                            }
                        }
                    }

                    Divider()

                    // ── What it is ────────────────────────────────────────────
                    InfoBlock(
                        icon: "book.fill",
                        title: "What it is",
                        text: info.what
                    )

                    // ── Why it matters ────────────────────────────────────────
                    InfoBlock(
                        icon: "target",
                        title: "Why it matters",
                        text: info.why
                    )

                    // ── How to improve ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Label("How to improve", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(info.iconColor)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(info.tips.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(info.iconColor.opacity(0.8))
                                        .padding(.top, 2)
                                    Text(tip)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }

                    Divider()

                    // ── Source ────────────────────────────────────────────────
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(info.source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .padding(.bottom, 20)
            }
            .navigationTitle(info.abbreviation)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Info block helper

private struct InfoBlock: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }
}

#Preview {
    MetricInfoSheet(info: MetricInfo.hrv(value: 48), currentValue: "48")
}
