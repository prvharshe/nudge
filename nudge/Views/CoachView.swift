import SwiftUI
import SwiftData

// MARK: - Data model

struct CoachMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let question: String
    let answer: String
    let date: Date
    var sources: CoachContextSources?

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        date: Date = .now,
        sources: CoachContextSources? = nil
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.date = date
        self.sources = sources
    }
}

private struct LiveCoachReply {
    let id: UUID
    let question: String
    var answer: String
    var sources: CoachContextSources?
    var startedAt: Date
    var hasToken: Bool
}

// MARK: - View

struct CoachView: View {
    @Query private var allEntries: [Entry]
    @State private var messages: [CoachMessage] = []
    @State private var live: LiveCoachReply? = nil
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var keepToast: String? = nil
    @State private var showKeepsSheet = false
    @State private var highlightedKeepID: UUID? = nil
    @State private var showMentionPicker = false
    @FocusState private var inputFocused: Bool

    @State private var keepStore = CoachKeepStore.shared

    private let storageKey = "nudge.coachMessages"
    private let minimumEntries = 5
    private var suggestions: [String] {
        var base = [
            "Why do I keep skipping certain days?",
            "What patterns do you see in my data?",
            "How has my consistency been lately?",
            "What activities do I do most often?"
        ]
        if UserDefaults.standard.string(forKey: "nudge.lastReportDate") != nil {
            base.insert("What does my blood report say about my fitness?", at: 0)
        }
        return base
    }

    private var isUnlocked: Bool { allEntries.count >= minimumEntries }

    var body: some View {
        NavigationStack {
            if isUnlocked {
                VStack(spacing: 0) {
                    if messages.isEmpty && live == nil {
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        messageList
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                            .transition(.opacity)
                    }

                    if showMentionPicker && !mentionCandidates.isEmpty {
                        mentionPicker
                    } else if !keepStore.isEmpty {
                        keepsChipStrip
                    }

                    Divider()
                    inputBar
                }
                .background(AmbientBackground())
                .overlay(alignment: .bottom) {
                    if let keepToast {
                        Text(keepToast)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black.opacity(0.75)))
                            .padding(.bottom, 88)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !keepStore.isEmpty {
                            Button {
                                highlightedKeepID = nil
                                showKeepsSheet = true
                            } label: {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(Theme.brandCoral)
                            }
                            .accessibilityLabel("Your keeps")
                        }
                    }

                    if !messages.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Clear") { clearMessages() }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .sheet(isPresented: $showKeepsSheet) {
                    CoachKeepsSheet(
                        keepStore: keepStore,
                        highlightedKeepID: highlightedKeepID,
                        onAskFollowUp: { keep in
                            inputText = "About this advice: \(keep.label) — "
                            inputFocused = true
                        }
                    )
                }
            } else {
                lockedState
                    .navigationTitle("Coach")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear { loadMessages() }
    }

    // MARK: - Locked state (not enough data yet)

    private var lockedState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Icon + title
                VStack(spacing: 14) {
                    Image(systemName: "lock.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.brandGradient)

                    VStack(spacing: 8) {
                        Text("Still learning your rhythm")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("Your coach needs at least \(minimumEntries) days of check-ins to spot real patterns and give you meaningful insights.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                    }
                }

                // Progress dots
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(0..<minimumEntries, id: \.self) { i in
                            ZStack {
                                Circle()
                                    .fill(i < allEntries.count
                                          ? Theme.green
                                          : Theme.card)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle().stroke(
                                            i < allEntries.count
                                                ? Theme.green.opacity(0.4)
                                                : Theme.brandCoral.opacity(0.25),
                                            lineWidth: 1
                                        )
                                    )

                                if i < allEntries.count {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }

                    Text(allEntries.isEmpty
                         ? "No check-ins yet — start tonight"
                         : "\(allEntries.count) of \(minimumEntries) days logged")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(allEntries.count > 0 ? .primary : .secondary)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 32)
                .background(Theme.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.purple.opacity(0.2), lineWidth: 1)
                )

                // Hint
                Label("Check in each evening from the Today tab", systemImage: "arrow.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmbientBackground())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.brandGradient)

                    Text("Ask your coach")
                        .font(.title2.bold())

                    Text("I have access to your full movement history.\nAsk me anything about your patterns.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            sendMessage(question: suggestion)
                        } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .surfaceCard(cornerRadius: 12)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.brandBorderGradient, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: keepStore.isEmpty ? 40 : 100)
            }
        }
        // Swipe down on the empty state to dismiss keyboard
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(messages) { msg in
                        MessageRow(
                            message: msg,
                            isKept: keepStore.isKept(id: msg.id),
                            showFollowUps: msg.id == messages.last?.id && live == nil,
                            onKeep: { toggleKeep(for: msg) },
                            onCopy: { copyAnswer(msg.answer) },
                            onFollowUp: { sendMessage(question: $0) }
                        )
                        .id(msg.id)
                    }
                    if let live {
                        liveReplyRow(live)
                            .id("live")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: live?.hasToken) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("live", anchor: .bottom)
                }
            }
            .onChange(of: live?.answer.count ?? 0) { _, count in
                if count > 0, count.isMultiple(of: 40) {
                    proxy.scrollTo("live", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func liveReplyRow(_ live: LiveCoachReply) -> some View {
        if live.hasToken {
            MessageRow(
                message: CoachMessage(
                    id: live.id,
                    question: live.question,
                    answer: live.answer,
                    sources: live.sources
                ),
                isKept: false,
                isStreaming: true,
                showFollowUps: false,
                onKeep: {},
                onCopy: { copyAnswer(live.answer) },
                onFollowUp: { _ in }
            )
        } else {
            CoachThinkingView(startedAt: live.startedAt, sources: live.sources)
        }
    }

    // MARK: - Keeps chip strip

    private var keepsChipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keepStore.keeps) { keep in
                    Button {
                        highlightedKeepID = keep.id
                        showKeepsSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2)
                            Text(keep.label)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .surfaceCard(cornerRadius: 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.brandBorderGradient, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var hasBloodReport: Bool {
        UserDefaults.standard.string(forKey: "nudge.lastReportDate") != nil
    }

    private var mentionCandidates: [CoachMention] {
        let query: String
        if let at = inputText.lastIndex(of: "@") {
            let after = String(inputText[inputText.index(after: at)...])
            if after.contains(where: { $0.isWhitespace }) { return [] }
            query = after.lowercased()
        } else if showMentionPicker {
            query = ""
        } else {
            return []
        }

        var items: [CoachMention] = []
        if hasBloodReport, query.isEmpty || "report".hasPrefix(query) || "blood".hasPrefix(query) {
            items.append(.report)
        }
        for keep in keepStore.keeps.prefix(6) {
            if query.isEmpty || keep.label.lowercased().contains(query) {
                items.append(.keep(keep))
            }
        }
        return items
    }

    private var mentionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mentionCandidates) { mention in
                    Button {
                        applyMention(mention)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mention.systemImage)
                                .font(.caption2)
                            Text(mention.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .surfaceCard(cornerRadius: 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.brandBorderGradient, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func applyMention(_ mention: CoachMention) {
        let insertion: String
        switch mention {
        case .report:
            insertion = "Using my blood report, "
        case .keep(let keep):
            insertion = "About this advice: \(keep.label) — "
        }

        if let at = inputText.lastIndex(of: "@"),
           !String(inputText[inputText.index(after: at)...]).contains(where: { $0.isWhitespace }) {
            inputText = String(inputText[..<at]) + insertion
        } else {
            inputText = insertion + inputText
        }
        showMentionPicker = false
        inputFocused = true
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                showMentionPicker.toggle()
                if showMentionPicker {
                    inputFocused = true
                }
            } label: {
                Image(systemName: "at.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        (showMentionPicker || !mentionCandidates.isEmpty)
                            ? Theme.brandCoral
                            : Theme.muted
                    )
            }
            .accessibilityLabel("Insert a source")
            .disabled(keepStore.isEmpty && !hasBloodReport)

            TextField("Ask about your patterns…", text: $inputText, axis: .vertical)
                .focused($inputFocused)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .surfaceCard(cornerRadius: 20)
                .onSubmit { sendMessage() }
                .onChange(of: inputText) { _, newValue in
                    if newValue.last == "@" {
                        showMentionPicker = true
                    } else if !newValue.contains("@") {
                        showMentionPicker = false
                    }
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Theme.brandCoral : Theme.muted)
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - Send

    private func sendMessage(question override: String? = nil) {
        let question = (override ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }

        inputText = ""
        inputFocused = false
        showMentionPicker = false
        isLoading = true
        errorMessage = nil
        live = LiveCoachReply(
            id: UUID(),
            question: question,
            answer: "",
            sources: nil,
            startedAt: .now,
            hasToken: false
        )

        // Build conversation history from the last 5 exchanges (10 turns)
        let recentMessages = messages.suffix(5)
        let history: [[String: String]] = recentMessages.flatMap { msg in
            [
                ["role": "user", "content": msg.question],
                ["role": "assistant", "content": msg.answer]
            ]
        }

        Task { @MainActor in
            do {
                for try await event in BackendService.askCoachStream(question: question, history: history) {
                    switch event {
                    case .retrieving:
                        break
                    case .generating(let incoming):
                        var next = live
                        next?.sources = incoming
                        live = next
                    case .token(let text):
                        let first = !(live?.hasToken ?? false)
                        var next = live
                        next?.answer += text
                        next?.hasToken = true
                        live = next
                        if first {
                            Haptics.impact(.light)
                        }
                    case .done:
                        break
                    }
                }

                let finalAnswer = (live?.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let finalSources = live?.sources
                let id = live?.id ?? UUID()
                live = nil
                guard !finalAnswer.isEmpty else {
                    isLoading = false
                    inputText = question
                    withAnimation { errorMessage = "Coach returned an empty answer. Try again." }
                    return
                }
                let msg = CoachMessage(
                    id: id,
                    question: question,
                    answer: finalAnswer,
                    sources: finalSources
                )
                withAnimation { messages.append(msg) }
                saveMessages()
                let count = messages.count
                if count == 3 || count == 8 {
                    let snapshot = messages
                    Task { await BackendService.saveConversation(snapshot) }
                }
                isLoading = false
            } catch {
                let partial = live?.answer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let sources = live?.sources
                let id = live?.id ?? UUID()
                live = nil
                if !partial.isEmpty {
                    let msg = CoachMessage(
                        id: id,
                        question: question,
                        answer: partial,
                        sources: sources
                    )
                    withAnimation { messages.append(msg) }
                    saveMessages()
                    isLoading = false
                    return
                }
                isLoading = false
                inputText = question
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't reach the coach. Check your connection."
                withAnimation { errorMessage = message }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { errorMessage = nil }
                }
            }
        }
    }

    // MARK: - Persistence

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CoachMessage].self, from: data)
        else { return }
        messages = decoded
    }

    private func saveMessages() {
        let toStore = Array(messages.suffix(20))
        if let data = try? JSONEncoder().encode(toStore) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func clearMessages() {
        // Save conversation to Supermemory before clearing
        if messages.count >= 2 {
            let snapshot = messages
            Task { await BackendService.saveConversation(snapshot) }
        }
        withAnimation {
            messages = []
            live = nil
        }
        isLoading = false
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Keeps

    private func toggleKeep(for message: CoachMessage) {
        if keepStore.isKept(id: message.id) {
            keepStore.unkeep(id: message.id)
            showKeepToast("Removed from keeps")
            Haptics.impact(.light)
            return
        }

        guard keepStore.keep(from: message) != nil else { return }

        Haptics.success()
        showKeepToast("Kept — Coach will remember this")

        let question = message.question
        let answer = message.answer
        let savedAt = Date.now
        Task {
            await BackendService.saveKeep(question: question, answer: answer, savedAt: savedAt)
        }
    }

    private func copyAnswer(_ answer: String) {
        UIPasteboard.general.string = answer
        Haptics.impact(.light)
        showKeepToast("Copied")
    }

    private func showKeepToast(_ message: String) {
        withAnimation {
            keepToast = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation {
                    if keepToast == message {
                        keepToast = nil
                    }
                }
            }
        }
    }
}

// MARK: - Mentions

private enum CoachMention: Identifiable {
    case report
    case keep(CoachKeep)

    var id: String {
        switch self {
        case .report: return "report"
        case .keep(let keep): return keep.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .report: return "Blood report"
        case .keep(let keep): return keep.label
        }
    }

    var systemImage: String {
        switch self {
        case .report: return "doc.text"
        case .keep: return "bookmark.fill"
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: CoachMessage
    let isKept: Bool
    var isStreaming: Bool = false
    var showFollowUps: Bool = false
    let onKeep: () -> Void
    let onCopy: () -> Void
    var onFollowUp: (String) -> Void = { _ in }

    private static let followUps = [
        "Explain that more simply",
        "Turn this into a short weekly plan",
        "What should I do next?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 56)
                Text(message.question)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .nocturnePrimaryButton(cornerRadius: 18)
            }

            HStack(alignment: .top, spacing: 10) {
                GradientIconBadge(systemName: "brain.head.profile", size: 28)

                VStack(alignment: .leading, spacing: 8) {
                    if let sources = message.sources, !sources.isEmpty {
                        CoachSourceChips(sources: sources)
                    }

                    MarkdownContentView(text: message.answer)
                    if isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .surfaceCard(cornerRadius: 18)
                .overlay(alignment: .topTrailing) {
                    if isKept {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.brandGradient)
                            .padding(8)
                    }
                }
                .contextMenu {
                    if !isStreaming {
                        if isKept {
                            Button(role: .destructive) {
                                onKeep()
                            } label: {
                                Label("Remove keep", systemImage: "bookmark.slash")
                            }
                        } else {
                            Button {
                                onKeep()
                            } label: {
                                Label("Keep this", systemImage: "bookmark")
                            }
                        }

                        Button {
                            onFollowUp("Explain that last answer in simpler terms.")
                        } label: {
                            Label("Explain", systemImage: "text.magnifyingglass")
                        }

                        Button {
                            onFollowUp("Shorten that last answer to 2–3 sentences.")
                        } label: {
                            Label("Shorten", systemImage: "arrow.down.right.and.arrow.up.left")
                        }

                        Button {
                            onFollowUp("Make that last answer more specific to my recent check-ins.")
                        } label: {
                            Label("Improve", systemImage: "sparkles")
                        }
                    }

                    Button {
                        onCopy()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                Spacer(minLength: 0)
            }

            if showFollowUps {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.followUps, id: \.self) { prompt in
                            Button {
                                onFollowUp(prompt)
                            } label: {
                                Text(prompt)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .surfaceCard(cornerRadius: 14)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Theme.brandBorderGradient, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, 38)
            }
        }
    }
}

// MARK: - Source chips

struct CoachSourceChips: View {
    let sources: CoachContextSources

    var body: some View {
        HStack(spacing: 6) {
            if sources.checkInCount > 0 {
                chip(
                    "\(sources.checkInCount) check-in\(sources.checkInCount == 1 ? "" : "s")",
                    "figure.run"
                )
            }
            if sources.profile > 0 {
                chip("Profile", "person.crop.circle")
            }
            if sources.keeps > 0 {
                chip(
                    "\(sources.keeps) keep\(sources.keeps == 1 ? "" : "s")",
                    "bookmark.fill"
                )
            }
        }
    }

    private func chip(_ title: String, _ systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.brandGradientSoft, in: Capsule())
    }
}

// MARK: - Thinking

struct CoachThinkingView: View {
    let startedAt: Date
    var sources: CoachContextSources?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GradientIconBadge(systemName: "brain.head.profile", size: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Thinking")
                        .font(.subheadline.weight(.medium))
                    TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
                        Text(elapsedLabel(context.date.timeIntervalSince(startedAt)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let sources, !sources.isEmpty {
                    CoachSourceChips(sources: sources)
                } else {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .surfaceCard(cornerRadius: 18)

            Spacer()
        }
    }

    private func elapsedLabel(_ interval: TimeInterval) -> String {
        String(format: "%.1fs", max(0, interval))
    }
}

// MARK: - Preview

#Preview {
    CoachView()
}
