import SwiftUI

// MARK: - Recovery Score

/// A 0–100 readiness score derived from resting HR, HRV, and sleep.
/// Each metric contributes a subscore, weighted by availability.
struct RecoveryScore {
    let value: Int      // 0–100
    let label: String   // "Tired" / "Fair" / "Good" / "Ready" / "Peak"
    let color: Color

    /// Returns nil only if all three inputs are nil.
    static func compute(rhr: Int?, hrv: Int?, sleepHours: Double?) -> RecoveryScore? {
        guard rhr != nil || hrv != nil || sleepHours != nil else { return nil }

        var weightedSum  = 0.0
        var totalWeight  = 0.0

        // ── Sleep (weight 40): optimal 7–8.5 h ───────────────────────────
        if let hours = sleepHours {
            let sub: Double
            switch hours {
            case 8.5...:     sub = 100
            case 7.0..<8.5:  sub = 75 + (hours - 7.0) / 1.5 * 25
            case 5.0..<7.0:  sub = 35 + (hours - 5.0) / 2.0 * 40
            default:         sub = max(0, hours / 5.0 * 35)
            }
            weightedSum += sub * 40
            totalWeight  += 40
        }

        // ── HRV (weight 30): higher = better recovery ─────────────────────
        if let ms = hrv {
            // 15 ms → 0 pts, 80 ms → 100 pts
            let sub = min(max(Double(ms - 15), 0) / 65.0, 1.0) * 100
            weightedSum += sub * 30
            totalWeight  += 30
        }

        // ── Resting HR (weight 30): lower = better ─────────────────────────
        if let bpm = rhr {
            // 45 BPM → 100 pts, 90 BPM → 0 pts
            let sub = min(max(Double(90 - bpm), 0) / 45.0, 1.0) * 100
            weightedSum += sub * 30
            totalWeight  += 30
        }

        let score = totalWeight > 0 ? Int((weightedSum / totalWeight).rounded()) : 0

        let (label, color): (String, Color)
        switch score {
        case 80...: (label, color) = ("Peak",  Color(hex: "34C759"))   // system green
        case 65..<80: (label, color) = ("Ready", Color(hex: "30D5C8")) // teal
        case 50..<65: (label, color) = ("Good",  Theme.blue)
        case 35..<50: (label, color) = ("Fair",  Color.orange)
        default:    (label, color) = ("Tired", Color.red)
        }

        return RecoveryScore(value: score, label: label, color: color)
    }
}
