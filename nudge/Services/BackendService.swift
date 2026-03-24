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
        let recovery = await HealthKitService.shared.fetchCurrentRecovery()
        if let hr = recovery.restingHR { urlString += "&restingHR=\(hr)" }
        if let hv = recovery.hrv       { urlString += "&hrv=\(hv)" }

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
