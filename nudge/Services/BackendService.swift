import Foundation

enum BackendService {
    private static var baseURL: String {
        UserDefaults.standard.string(forKey: "nudge.backendURL") ?? "https://nudge-production-7890.up.railway.app"
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
        guard let url = URL(string: "\(baseURL)/api/coach") else {
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONDecoder().decode(CoachResponse.self, from: data)
        return json.answer
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
            if let json = try? JSONDecoder().decode([String: String].self, from: responseData),
               let errMsg = json["error"] {
                throw NSError(domain: "ReportUpload", code: 0, userInfo: [NSLocalizedDescriptionKey: errMsg])
            }
            throw URLError(.badServerResponse)
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
}

private struct NudgeResponse: Decodable {
    let message: String
}

private struct CoachResponse: Decodable {
    let answer: String
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
