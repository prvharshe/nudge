import Foundation

enum BackendError: LocalizedError {
    case unreachable
    case serverUnavailable(status: Int)
    case badResponse(String?)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Couldn't reach the coach. Check your connection."
        case .serverUnavailable:
            return "Coach is temporarily unavailable. Try again in a moment."
        case .badResponse(let message):
            return message ?? "Coach couldn't answer that. Try again."
        }
    }
}

enum BackendService {
    private static let productionURL = "https://nudge-backend-40994690021.asia-south1.run.app"

    /// Production Cloud Run URL. Debug builds may override via Settings → Backend URL.
    private static var baseURL: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "nudge.backendURL")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        #endif
        return productionURL
    }

    // MARK: - Sync entry to Supermemory via backend
    static func syncEntry(_ entry: Entry, stats: DayStats? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/api/entries") else { return }

        let formatter = ISO8601DateFormatter()
        var body: [String: Any] = [
            "userId": UserService.userId,
            "date": formatter.string(from: entry.date),
            "didMove": entry.didMove,
            "activities": entry.activities,
            "note": entry.note as Any
        ]
        if let s = stats {
            body["steps"] = s.steps
            if let m = s.workoutMinutes { body["workoutMinutes"] = m }
            if let c = s.calories       { body["calories"] = c }
            if let t = s.workoutType    { body["workoutType"] = t }
            if let sh = s.sleepHours    { body["sleepHours"] = sh }
            if let hr = s.restingHR     { body["restingHR"] = hr }
            if let hv = s.hrv           { body["hrv"] = hv }
            if let fc = s.foodCalories { body["foodCalories"] = fc }
            if let pr = s.protein      { body["protein"] = pr }
            if let cb = s.carbs        { body["carbs"] = cb }
            if let ft = s.fat          { body["fat"] = ft }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Fetch morning nudge message
    static func fetchNudge(refresh: Bool = false) async throws -> String {
        let userId = UserService.userId
        let userName = UserDefaults.standard.string(forKey: "nudge.userName") ?? ""
        var urlString = "\(baseURL)/api/nudge?userId=\(userId)"
        if !userName.isEmpty,
           let encoded = userName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&userName=\(encoded)"
        }
        if refresh { urlString += "&refresh=true" }

        let userGoal = UserDefaults.standard.string(forKey: "nudge.userGoal") ?? ""
        if !userGoal.isEmpty { urlString += "&goal=\(userGoal)" }

        let profile = UserProfile.summary
        if !profile.isEmpty,
           let encoded = profile.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&profileSummary=\(encoded)"
        }

        // Attach today's recovery signal so Groq can adapt the nudge tone
        async let statsResult    = HealthKitService.shared.fetchStats(for: .now)
        async let recoveryResult = HealthKitService.shared.fetchCurrentRecovery()
        let (stats, recovery)    = await (statsResult, recoveryResult)
        if let hr = recovery.restingHR { urlString += "&restingHR=\(hr)" }
        if let hv = recovery.hrv       { urlString += "&hrv=\(hv)" }
        let score = RecoveryScore.compute(
            rhr:        recovery.restingHR,
            hrv:        recovery.hrv,
            sleepHours: stats?.sleepHours
        )
        if let s = score { urlString += "&recoveryScore=\(s.value)&recoveryLabel=\(s.label)" }

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONDecoder().decode(NudgeResponse.self, from: data)
        return json.message
    }

    // MARK: - Ask your coach (free-form Q&A against Supermemory history)

    static func askCoach(question: String, history: [[String: String]] = []) async throws -> String {
        let request = try coachURLRequest(path: "/api/coach", question: question, history: history)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try throwIfCoachHTTPError(response, data: data)
            let json = try JSONDecoder().decode(CoachResponse.self, from: data)
            return json.answer
        } catch let error as BackendError {
            throw error
        } catch let error as URLError {
            throw mapCoachURLError(error)
        } catch is DecodingError {
            throw BackendError.badResponse(nil)
        }
    }

    /// Stream a coach answer over SSE (`POST /api/coach/stream`).
    /// Falls back to the blocking JSON endpoint if the stream route is missing.
    static func askCoachStream(
        question: String,
        history: [[String: String]] = []
    ) -> AsyncThrowingStream<CoachStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try coachURLRequest(
                        path: "/api/coach/stream",
                        question: question,
                        history: history
                    )
                    let tokenCount = try await consumeCoachSSE(
                        request: request,
                        continuation: continuation
                    )
                    // Zero tokens: GPT-OSS/reasoning-only or a parser miss — use JSON.
                    if tokenCount == 0 {
                        throw CoachStreamUnavailable()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as CoachStreamUnavailable {
                    do {
                        let answer = try await askCoach(question: question, history: history)
                        continuation.yield(.token(answer))
                        continuation.yield(.done)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch let error as URLError {
                    continuation.finish(throwing: mapCoachURLError(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct CoachStreamUnavailable: Error {}

    private static func coachURLRequest(
        path: String,
        question: String,
        history: [[String: String]]
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }

        let goal = UserDefaults.standard.string(forKey: "nudge.userGoal") ?? ""
        var body: [String: Any] = [
            "userId": UserService.userId,
            "question": question,
            "history": history
        ]
        if !goal.isEmpty { body["goal"] = goal }
        let coachProfile = UserProfile.summary
        if !coachProfile.isEmpty { body["profileSummary"] = coachProfile }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if path.hasSuffix("/stream") {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Cold start + retrieval + Groq; stream stays open until done.
        request.timeoutInterval = 90
        return request
    }

    private static func throwIfCoachHTTPError(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.unreachable
        }
        guard http.statusCode == 200 else {
            let serverMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? String }
            if http.statusCode == 503, let serverMsg {
                throw BackendError.badResponse(serverMsg)
            }
            if (500...599).contains(http.statusCode) {
                throw BackendError.serverUnavailable(status: http.statusCode)
            }
            throw BackendError.badResponse(serverMsg)
        }
    }

    private static func mapCoachURLError(_ error: URLError) -> BackendError {
        switch error.code {
        case .timedOut, .notConnectedToInternet, .networkConnectionLost,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .unreachable
        default:
            return .serverUnavailable(status: -1)
        }
    }

    /// Parse SSE from raw bytes. Do not use `bytes.lines` — it omits the blank
    /// lines that terminate SSE events, so every event would be flushed as `done`.
    private static func consumeCoachSSE(
        request: URLRequest,
        continuation: AsyncThrowingStream<CoachStreamEvent, Error>.Continuation
    ) async throws -> Int {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.unreachable
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if http.statusCode == 404 || !contentType.contains("text/event-stream") {
            throw CoachStreamUnavailable()
        }
        if http.statusCode != 200 {
            throw BackendError.serverUnavailable(status: http.statusCode)
        }

        var buffer = Data()
        buffer.reserveCapacity(1024)
        var tokenCount = 0

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            while let boundary = sseEventBoundary(in: buffer) {
                let block = buffer.subdata(in: 0..<boundary.end)
                buffer.removeSubrange(0..<boundary.next)
                tokenCount += try emitSSEBlock(block, continuation: continuation)
            }
        }
        if !buffer.isEmpty {
            tokenCount += try emitSSEBlock(buffer, continuation: continuation)
        }
        return tokenCount
    }

    private static func sseEventBoundary(in buffer: Data) -> (end: Int, next: Int)? {
        if let range = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
            return (range.lowerBound, range.upperBound)
        }
        if let range = buffer.range(of: Data([0x0A, 0x0A])) {
            return (range.lowerBound, range.upperBound)
        }
        return nil
    }

    private static func emitSSEBlock(
        _ block: Data,
        continuation: AsyncThrowingStream<CoachStreamEvent, Error>.Continuation
    ) throws -> Int {
        guard let text = String(data: block, encoding: .utf8) else { return 0 }

        var eventName = "message"
        var dataLines: [String] = []

        func flush() throws -> Int {
            guard !dataLines.isEmpty else {
                eventName = "message"
                return 0
            }
            let data = dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            let name = eventName
            eventName = "message"
            return try emitCoachSSE(event: name, data: data, continuation: continuation)
        }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var tokens = 0
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(":") { continue }
            if line.isEmpty {
                tokens += try flush()
                continue
            }
            // If blank delimiters were lost, a new `event:` starts the next frame.
            if line.hasPrefix("event:"), !dataLines.isEmpty {
                tokens += try flush()
            }
            if line.hasPrefix("event:") {
                eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
            }
        }
        tokens += try flush()
        return tokens
    }

    @discardableResult
    private static func emitCoachSSE(
        event: String,
        data: String,
        continuation: AsyncThrowingStream<CoachStreamEvent, Error>.Continuation
    ) throws -> Int {
        switch event {
        case "token":
            if let text = decodeSSEText(data), !text.isEmpty {
                continuation.yield(.token(text))
                return 1
            }
            return 0
        case "meta":
            if let meta = decodeSSEMeta(data) {
                if meta.stage == "retrieving" {
                    continuation.yield(.retrieving)
                } else if meta.stage == "generating" {
                    continuation.yield(.generating(meta.sources ?? .empty))
                }
            }
            return 0
        case "error":
            let message = decodeSSEError(data) ?? "Failed to generate answer"
            throw BackendError.badResponse(message)
        case "done":
            continuation.yield(.done)
            return 0
        default:
            return 0
        }
    }

    private static func decodeSSEText(_ data: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            return data.isEmpty ? nil : data
        }
        return json["text"] as? String
    }

    private static func decodeSSEError(_ data: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            return data
        }
        return json["error"] as? String
    }

    private static func decodeSSEMeta(_ data: String) -> CoachSSEMeta? {
        try? JSONDecoder().decode(CoachSSEMeta.self, from: Data(data.utf8))
    }

    // MARK: - Post-log one-sentence reaction

    static func fetchReaction(didMove: Bool, activities: [String]) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/reaction") else {
            throw URLError(.badURL)
        }

        let goal = UserDefaults.standard.string(forKey: "nudge.userGoal") ?? ""
        var body: [String: Any] = [
            "userId": UserService.userId,
            "didMove": didMove,
            "activities": activities
        ]
        if !goal.isEmpty { body["goal"] = goal }
        let reactionProfile = UserProfile.summary
        if !reactionProfile.isEmpty { body["profileSummary"] = reactionProfile }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONDecoder().decode(ReactionResponse.self, from: data)
        return json.reaction
    }

    // MARK: - Weekly pattern insight

    static func fetchWeeklyInsight() async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/weekly") else {
            throw URLError(.badURL)
        }

        let goal = UserDefaults.standard.string(forKey: "nudge.userGoal") ?? ""
        var body: [String: Any] = ["userId": UserService.userId]
        if !goal.isEmpty { body["goal"] = goal }
        let weeklyProfile = UserProfile.summary
        if !weeklyProfile.isEmpty { body["profileSummary"] = weeklyProfile }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONDecoder().decode(WeeklyResponse.self, from: data)
        return json.insight
    }

    // MARK: - Memory type

    enum MemoryType: String {
        case profile, insight, milestone, convo, context
    }

    // MARK: - Store a typed memory in Supermemory

    /// Fire-and-forget — never throws. Errors are silently dropped.
    static func storeMemory(type: MemoryType, content: String) async {
        guard let url = URL(string: "\(baseURL)/api/memories") else { return }
        let body: [String: Any] = [
            "userId": UserService.userId,
            "type": type.rawValue,
            "content": content
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Save a kept coach reply to Supermemory

    /// Fire-and-forget — stores user-anchored advice as an `insight` memory.
    static func saveKeep(question: String, answer: String, savedAt: Date) async {
        let formatter = ISO8601DateFormatter()
        let date = formatter.string(from: savedAt)
        let content = "[Kept coach advice on \(date)] Q: \(question) A: \(answer)"
        await storeMemory(type: .insight, content: content)
    }

    // MARK: - Save coach conversation summary

    /// Sends conversation turns to backend; Groq summarises and stores in Supermemory.
    /// Silent no-op if fewer than 2 messages.
    static func saveConversation(_ messages: [CoachMessage]) async {
        guard messages.count >= 2,
              let url = URL(string: "\(baseURL)/api/memories/summarize-convo") else { return }
        let history = messages.flatMap { msg in
            [["role": "user",      "content": msg.question],
             ["role": "assistant", "content": msg.answer]]
        }
        let body: [String: Any] = ["userId": UserService.userId, "messages": history]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Fetch daily learn insight (cached per day in UserDefaults)

    static func fetchLearnInsight(
        restingHR:     Int?    = nil,
        hrv:           Int?    = nil,
        sleepHours:    Double? = nil,
        steps:         Int?    = nil,
        recoveryScore: Int?    = nil,
        recoveryLabel: String? = nil
    ) async throws -> String {
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: .now))
        let cacheDate = UserDefaults.standard.string(forKey: "nudge.learnInsight.date") ?? ""
        if cacheDate == today,
           let cached = UserDefaults.standard.string(forKey: "nudge.learnInsight.text"), !cached.isEmpty {
            return cached
        }

        guard let url = URL(string: "\(baseURL)/api/learn") else { throw URLError(.badURL) }

        var body: [String: Any] = ["userId": UserService.userId]
        if let v = restingHR     { body["restingHR"]     = v }
        if let v = hrv           { body["hrv"]           = v }
        if let v = sleepHours    { body["sleepHours"]    = v }
        if let v = steps         { body["steps"]         = v }
        if let v = recoveryScore { body["recoveryScore"] = v }
        if let v = recoveryLabel { body["recoveryLabel"] = v }

        let goal = UserDefaults.standard.string(forKey: "nudge.userGoal") ?? ""
        if !goal.isEmpty { body["goal"] = goal }
        let profile = UserProfile.summary
        if !profile.isEmpty { body["profileSummary"] = profile }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONDecoder().decode(LearnResponse.self, from: data)
        UserDefaults.standard.set(today,       forKey: "nudge.learnInsight.date")
        UserDefaults.standard.set(json.insight, forKey: "nudge.learnInsight.text")
        return json.insight
    }

    // MARK: - Upload and analyse a health report

    struct ReportResult {
        let insights: [String]
        let biomarkers: [String: BiomarkerEntry]
        let reportDate: String
    }

    struct BiomarkerEntry: Decodable {
        let name: String
        let value: String          // kept as String — could be "14.2" or "<5"
        let unit: String?
        let status: String?        // "normal" | "low" | "high" | "borderline"
        let reference: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name      = try c.decode(String.self, forKey: .name)
            // value can be number or string in the JSON
            if let d = try? c.decode(Double.self, forKey: .value) {
                value = d.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(d)) : String(d)
            } else {
                value = (try? c.decode(String.self, forKey: .value)) ?? ""
            }
            unit      = try? c.decode(String.self, forKey: .unit)
            status    = try? c.decode(String.self, forKey: .status)
            reference = try? c.decode(String.self, forKey: .reference)
        }

        enum CodingKeys: String, CodingKey {
            case name, value, unit, status, reference
        }
    }

    static func uploadReport(
        data: Data,
        filename: String,
        mimeType: String,
        hkMetrics: [String: Any] = [:]
    ) async throws -> ReportResult {
        guard let url = URL(string: "\(baseURL)/api/reports/upload") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString
        var body = Data()

        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }

        // userId field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n")
        append("\(UserService.userId)\r\n")

        // hkMetrics field
        if let metricsJSON = try? JSONSerialization.data(withJSONObject: hkMetrics),
           let metricsStr = String(data: metricsJSON, encoding: .utf8) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"hkMetrics\"\r\n\r\n")
            append("\(metricsStr)\r\n")
        }

        // profileSummary field
        let profile = UserProfile.summary
        if !profile.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"profileSummary\"\r\n\r\n")
            append("\(profile)\r\n")
        }

        // file field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Try to surface the actual server error message
            let serverMsg = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])
                .flatMap { $0["error"] as? String }
                ?? String(data: responseData, encoding: .utf8)?.prefix(300).description
                ?? "Server error"
            throw NSError(domain: "ReportUpload", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: serverMsg])
        }

        let json = try JSONDecoder().decode(ReportUploadResponse.self, from: responseData)

        // Save report date to UserDefaults for Coach suggestion chip
        let today = ISO8601DateFormatter().string(from: .now)
        UserDefaults.standard.set(today, forKey: "nudge.lastReportDate")

        return ReportResult(
            insights: json.insights,
            biomarkers: json.biomarkers ?? [:],
            reportDate: json.reportDate
        )
    }

    // MARK: - Delete all Supermemory entries for this user
    static func deleteSupermemoryData() async throws -> (deleted: Int, failed: Int) {
        let userId = UserService.userId
        guard let url = URL(string: "\(baseURL)/api/entries?userId=\(userId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONDecoder().decode(DeleteResponse.self, from: data)
        return (json.deleted, json.failed)
    }

    // MARK: - Restore entries from backend
    static func restoreEntries() async throws -> [RestoredEntry] {
        guard let url = URL(string: "\(baseURL)/api/entries?userId=\(UserService.userId)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(EntryRestoreResponse.self, from: data).entries
    }

    // MARK: - Check if user has entries in Supermemory (for recovery prompt)
    static func checkUserHasEntries() async -> EntryExistenceResult? {
        let userId = UserService.userId
        guard let url = URL(string: "\(baseURL)/api/entries/exists?userId=\(userId)") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(EntryExistenceResult.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Recovery code

    static func registerRecoveryCode() async {
        guard let url = URL(string: "\(baseURL)/api/recovery/register") else { return }
        let body = ["userId": UserService.userId, "recoveryCode": UserService.recoveryCode]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: request)
    }

    static func restoreAccount(recoveryCode: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/recovery/restore") else {
            throw URLError(.badURL)
        }
        let normalizedCode = recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["recoveryCode": normalizedCode])
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }
        let userId = try JSONDecoder().decode(AccountRestoreResponse.self, from: data).userId
        UserService.restoreAccount(userId: userId, recoveryCode: normalizedCode)
        await registerRecoveryCode()
    }

    /// Last resort: scan ALL nudge entries from Supermemory (no userId filter)
    static func recoverAllEntries() async -> [RestoredEntry] {
        guard let url = URL(string: "\(baseURL)/api/entries/recover-all") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let result = try? JSONDecoder().decode(EntryRestoreResponse.self, from: data) else {
            return []
        }
        return result.entries
    }

    /// Manually claim data from another userId (if the user knows their old userId)
    static func restoreEntriesForUserId(_ oldUserId: String) async throws -> [RestoredEntry] {
        guard let url = URL(string: "\(baseURL)/api/entries?userId=\(oldUserId)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(EntryRestoreResponse.self, from: data).entries
    }
}

private struct NudgeResponse: Decodable {
    let message: String
}

private struct CoachResponse: Decodable {
    let answer: String
}

private struct CoachSSEMeta: Decodable {
    let stage: String?
    let sources: CoachContextSources?
}

private struct ReactionResponse: Decodable {
    let reaction: String
}

private struct WeeklyResponse: Decodable {
    let insight: String
}

private struct DeleteResponse: Decodable {
    let deleted: Int
    let failed: Int
}

private struct LearnResponse: Decodable {
    let insight: String
}

private struct ReportUploadResponse: Decodable {
    let ok: Bool
    let insights: [String]
    let biomarkers: [String: BackendService.BiomarkerEntry]?
    let reportDate: String
}

struct EntryExistenceResult: Decodable {
    let hasEntries: Bool
    let count: Int
    let latestDate: String?
}

struct RestoredEntry: Decodable {
    let date: String
    let didMove: Bool
    let activities: [String]
    let note: String?
}

private struct EntryRestoreResponse: Decodable {
    let entries: [RestoredEntry]
}

private struct AccountRestoreResponse: Decodable {
    let userId: String
}
