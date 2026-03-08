import Foundation

enum BackendService {
    private static var baseURL: String {
        UserDefaults.standard.string(forKey: "nudge.backendURL") ?? "http://192.168.2.200:3000"
    }

    // MARK: - Sync entry to Supermemory via backend
    static func syncEntry(_ entry: Entry) async throws {
        guard let url = URL(string: "\(baseURL)/api/entries") else { return }

        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = [
            "userId": UserService.userId,
            "date": formatter.string(from: entry.date),
            "didMove": entry.didMove,
            "activities": entry.activities,
            "note": entry.note as Any
        ]

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
    static func fetchNudge() async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/nudge?userId=\(UserService.userId)") else {
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

private struct DeleteResponse: Decodable {
    let deleted: Int
    let failed: Int
}
