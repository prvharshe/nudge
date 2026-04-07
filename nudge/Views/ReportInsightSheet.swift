import SwiftUI

struct ReportInsightSheet: View {
    let result: BackendService.ReportResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // ── Header ────────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Health Report Analysis", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(result.reportDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // ── Biomarkers ────────────────────────────────────────────
                    if !result.biomarkers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Key Markers Found")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(
                                        result.biomarkers.values.sorted { $0.name < $1.name },
                                        id: \.name
                                    ) { marker in
                                        BiomarkerChip(marker: marker)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    // ── Insights ──────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Personalised Insights")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        VStack(spacing: 10) {
                            ForEach(Array(result.insights.enumerated()), id: \.offset) { _, insight in
                                InsightRow(text: insight)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // ── Coach CTA ─────────────────────────────────────────────
                    VStack(spacing: 8) {
                        Label("Ask your coach about this report", systemImage: "brain")
                            .font(.subheadline.weight(.medium))
                        Text("Your report is saved to Coach memory — just ask anything.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Theme.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.purple.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Report Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Biomarker chip

private struct BiomarkerChip: View {
    let marker: BackendService.BiomarkerEntry

    private var statusColor: Color {
        switch marker.status?.lowercased() {
        case "low":         return .orange
        case "high":        return .red
        case "borderline":  return .yellow
        case "normal":      return Theme.green
        default:            return .secondary
        }
    }

    private var statusIcon: String {
        switch marker.status?.lowercased() {
        case "low":         return "arrow.down.circle.fill"
        case "high":        return "arrow.up.circle.fill"
        case "borderline":  return "exclamationmark.circle.fill"
        case "normal":      return "checkmark.circle.fill"
        default:            return "minus.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                Text(marker.status?.capitalized ?? "—")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            Text(marker.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(marker.value)\(marker.unit.map { " \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(statusColor.opacity(0.2), lineWidth: 1)
        )
        .frame(minWidth: 90)
    }
}

// MARK: - Insight row

private struct InsightRow: View {
    let text: String

    // Bold the first segment up to a colon or end of the bold marker
    private var attributed: AttributedString {
        var attributed = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        return attributed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
                .padding(.top, 3)

            Text(attributed)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
