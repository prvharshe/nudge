import SwiftUI
import SwiftData
import Combine

// MARK: - Data model

struct CoachMessage: Codable, Identifiable {
    let id: UUID
    let question: String
    let answer: String
    let date: Date

    init(question: String, answer: String) {
        self.id = UUID()
        self.question = question
        self.answer = answer
        self.date = Date.now
    }
}

// MARK: - View

struct CoachView: View {
    @Query private var allEntries: [Entry]
    @State private var messages: [CoachMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @FocusState private var inputFocused: Bool

    private let storageKey = "nudge.coachMessages"
    private let minimumEntries = 5
    private let suggestions = [
        "Why do I keep skipping certain days?",
        "What patterns do you see in my data?",
        "How has my consistency been lately?",
        "What activities do I do most often?"
    ]

    private var isUnlocked: Bool { allEntries.count >= minimumEntries }

    var body: some View {
        NavigationStack {
            if isUnlocked {
                VStack(spacing: 0) {
                    if messages.isEmpty && !isLoading {
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

                    Divider()
                    inputBar
                }
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !messages.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Clear") { clearMessages() }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    Text("🔒")
                        .font(.system(size: 52))

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
                                                : Theme.purple.opacity(0.2),
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Text("🧠")
                        .font(.system(size: 52))

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
                            inputText = suggestion
                            sendMessage()
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
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
        // Swipe down on the empty state to dismiss keyboard
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { inputFocused = false }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(messages) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                    }
                    if isLoading {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            // Swipe down on the message list to dismiss keyboard → tab bar becomes reachable
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: isLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your patterns…", text: $inputText, axis: .vertical)
                .focused($inputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Theme.blue : Theme.muted)
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - Send

    private func sendMessage() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }

        inputText = ""
        inputFocused = false
        isLoading = true
        errorMessage = nil

        // Build conversation history from the last 5 exchanges (10 turns)
        let recentMessages = messages.suffix(5)
        let history: [[String: String]] = recentMessages.flatMap { msg in
            [
                ["role": "user", "content": msg.question],
                ["role": "assistant", "content": msg.answer]
            ]
        }

        Task {
            do {
                let answer = try await BackendService.askCoach(question: question, history: history)
                await MainActor.run {
                    let msg = CoachMessage(question: question, answer: answer)
                    withAnimation { messages.append(msg) }
                    saveMessages()
                    // Auto-save conversation to Supermemory at 3 and 8 exchanges
                    let count = messages.count
                    if count == 3 || count == 8 {
                        let snapshot = messages
                        Task { await BackendService.saveConversation(snapshot) }
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    withAnimation { errorMessage = "Couldn't reach the coach. Check your connection." }
                    // Clear the error after 4 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        await MainActor.run {
                            withAnimation { errorMessage = nil }
                        }
                    }
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
        withAnimation { messages = [] }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: CoachMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Question bubble (user, trailing)
            HStack {
                Spacer(minLength: 56)
                Text(message.question)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            // Answer (coach, leading)
            HStack(alignment: .top, spacing: 10) {
                Text("🧠")
                    .font(.system(size: 22))
                    .padding(.top, 2)

                Text(message.answer)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("🧠")
                .font(.system(size: 22))
                .padding(.top, 2)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(phase == i ? 0.9 : 0.3))
                        .frame(width: 7, height: 7)
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Preview

#Preview {
    CoachView()
}
