import SwiftUI
import UniformTypeIdentifiers

struct UploadReportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showDocumentPicker = false
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    @State private var result: BackendService.ReportResult? = nil
    @State private var showInsightSheet = false

    private let supportedTypes: [UTType] = [.pdf, .jpeg, .png, .heic, .webP]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // ── Icon + Explainer ──────────────────────────────────────
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Theme.blue.opacity(0.1))
                                .frame(width: 88, height: 88)
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundStyle(Theme.blue)
                        }

                        VStack(spacing: 8) {
                            Text("Upload a Health Report")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)

                            Text("Blood tests, metabolic panels, lipid profiles — any lab report. We'll extract your biomarkers and generate personalised insights connecting them to your fitness data.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 16)
                        }
                    }

                    // ── Supported formats ─────────────────────────────────────
                    HStack(spacing: 16) {
                        FormatPill(icon: "doc.fill", label: "PDF")
                        FormatPill(icon: "photo", label: "JPEG")
                        FormatPill(icon: "photo", label: "PNG")
                        FormatPill(icon: "photo", label: "HEIC")
                    }

                    // ── Privacy note ──────────────────────────────────────────
                    Label("Your report is processed and immediately discarded. Only a structured summary is stored.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.horizontal, 24)

                Spacer()

                // ── Error message ─────────────────────────────────────────────
                if let error = uploadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                // ── CTA Button ────────────────────────────────────────────────
                Button {
                    uploadError = nil
                    showDocumentPicker = true
                } label: {
                    Group {
                        if isUploading {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(.white)
                                Text("Analysing report…")
                                    .font(.subheadline.weight(.semibold))
                            }
                        } else {
                            Label("Choose File", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(isUploading ? Theme.blue.opacity(0.6) : Theme.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(isUploading)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Health Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showDocumentPicker,
                allowedContentTypes: supportedTypes,
                allowsMultipleSelection: false
            ) { fileResult in
                handleFileSelection(fileResult)
            }
            .sheet(isPresented: $showInsightSheet) {
                if let r = result {
                    ReportInsightSheet(result: r)
                        .onDisappear { dismiss() }
                }
            }
        }
    }

    // MARK: - File handling

    private func handleFileSelection(_ fileResult: Result<[URL], Error>) {
        switch fileResult {
        case .failure(let err):
            uploadError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            isUploading = true
            uploadError = nil
            Task { await upload(url: url) }
        }
    }

    private func upload(url: URL) async {
        // Security-scoped resource access
        guard url.startAccessingSecurityScopedResource() else {
            await MainActor.run {
                isUploading = false
                uploadError = "Couldn't access the file. Please try again."
            }
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let mimeType = mimeType(for: url)
            let filename = url.lastPathComponent

            // Attach today's HK metrics for richer insights
            var hkMetrics: [String: Any] = [:]
            async let statsResult    = HealthKitService.shared.fetchStats(for: .now)
            async let recoveryResult = HealthKitService.shared.fetchCurrentRecovery()
            let (stats, recovery)    = await (statsResult, recoveryResult)
            if let steps = stats?.steps          { hkMetrics["steps"] = steps }
            if let sleep = stats?.sleepHours     { hkMetrics["sleepHours"] = sleep }
            if let rhr   = recovery.restingHR    { hkMetrics["restingHR"] = rhr }
            if let hrv   = recovery.hrv          { hkMetrics["hrv"] = hrv }
            if let score = RecoveryScore.compute(rhr: recovery.restingHR, hrv: recovery.hrv, sleepHours: stats?.sleepHours) {
                hkMetrics["recoveryScore"] = score.value
                hkMetrics["recoveryLabel"] = score.label
            }

            let uploadResult = try await BackendService.uploadReport(
                data: data,
                filename: filename,
                mimeType: mimeType,
                hkMetrics: hkMetrics
            )

            await MainActor.run {
                isUploading = false
                result = uploadResult
                showInsightSheet = true
            }
        } catch {
            await MainActor.run {
                isUploading = false
                uploadError = error.localizedDescription
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":         return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "heic":        return "image/heic"
        case "webp":        return "image/webp"
        default:            return "application/octet-stream"
        }
    }
}

// MARK: - Format pill

private struct FormatPill: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.blue)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
