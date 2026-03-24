import Foundation

// MARK: - Biological Sex

enum UserSex: String, CaseIterable {
    case male   = "male"
    case female = "female"
    case other  = "other"

    var title: String {
        switch self {
        case .male:   return "Male"
        case .female: return "Female"
        case .other:  return "Other"
        }
    }

    /// Mifflin-St Jeor constant (+5 male, -161 female)
    fileprivate var bmrConstant: Double {
        switch self {
        case .male:   return 5.0
        case .female: return -161.0
        case .other:  return -78.0   // midpoint
        }
    }
}

// MARK: - Daily Activity Level (lifestyle, outside dedicated workouts)

enum ActivityLevel: String, CaseIterable {
    case sedentary  = "sedentary"
    case light      = "light"
    case moderate   = "moderate"
    case veryActive = "very_active"

    var emoji: String {
        switch self {
        case .sedentary:  return "🪑"
        case .light:      return "🚶"
        case .moderate:   return "💪"
        case .veryActive: return "🔥"
        }
    }

    var title: String {
        switch self {
        case .sedentary:  return "Sedentary"
        case .light:      return "Lightly active"
        case .moderate:   return "Moderately active"
        case .veryActive: return "Very active"
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary:  return "Desk job, mostly sitting"
        case .light:      return "Some walking, on feet part of the day"
        case .moderate:   return "Active job or consistent workouts"
        case .veryActive: return "Intense training or very physical job"
        }
    }

    /// PAL multiplier for TDEE calculation
    fileprivate var palMultiplier: Double {
        switch self {
        case .sedentary:  return 1.20
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .veryActive: return 1.725
        }
    }
}

// MARK: - UserProfile namespace (reads/writes UserDefaults)

enum UserProfile {

    // MARK: Stored values

    static var sex: UserSex? {
        UserDefaults.standard.string(forKey: "nudge.sex").flatMap { UserSex(rawValue: $0) }
    }
    static var age: Int? {
        let v = UserDefaults.standard.integer(forKey: "nudge.age")
        return v > 0 ? v : nil
    }
    static var heightCm: Double? {
        let v = UserDefaults.standard.double(forKey: "nudge.heightCm")
        return v > 0 ? v : nil
    }
    static var weightKg: Double? {
        let v = UserDefaults.standard.double(forKey: "nudge.weightKg")
        return v > 0 ? v : nil
    }
    static var activityLevel: ActivityLevel? {
        UserDefaults.standard.string(forKey: "nudge.activityLevel")
            .flatMap { ActivityLevel(rawValue: $0) }
    }

    // MARK: Derived metrics

    static var bmi: Double? {
        guard let h = heightCm, let w = weightKg, h > 0 else { return nil }
        return w / pow(h / 100.0, 2)
    }

    /// Mifflin-St Jeor BMR (kcal/day at complete rest)
    static var bmr: Double? {
        guard let h = heightCm, let w = weightKg, let a = age else { return nil }
        let s = sex ?? .other
        return 10 * w + 6.25 * h - 5 * Double(a) + s.bmrConstant
    }

    /// Total Daily Energy Expenditure
    static var tdee: Double? {
        guard let b = bmr, let al = activityLevel else { return nil }
        return b * al.palMultiplier
    }

    /// Protein target (g/day), adjusted to the user's goal
    static var proteinTargetG: Int? {
        guard let w = weightKg else { return nil }
        let goal = UserDefaults.standard.string(forKey: "nudge.userGoal") ?? ""
        let gPerKg: Double
        switch goal {
        case "build_muscle":      gPerKg = 1.6
        case "lose_weight":       gPerKg = 1.2
        case "improve_endurance": gPerKg = 1.4
        default:                  gPerKg = 1.0
        }
        return Int(w * gPerKg)
    }

    // MARK: Natural-language summary for Groq

    /// One-sentence profile context injected into every Groq prompt.
    static var summary: String {
        var parts: [String] = []

        switch (age, sex) {
        case let (a?, s?): parts.append("\(a)-year-old \(s.title.lowercased())")
        case let (a?, _):  parts.append("\(a) years old")
        case let (_, s?):  parts.append(s.title.lowercased())
        default: break
        }

        if let h = heightCm, let w = weightKg, let b = bmi {
            parts.append(String(format: "%.0fcm / %.0fkg (BMI %.1f)", h, w, b))
        } else if let h = heightCm {
            parts.append(String(format: "%.0fcm", h))
        } else if let w = weightKg {
            parts.append(String(format: "%.0fkg", w))
        }

        if let al = activityLevel {
            parts.append("\(al.title.lowercased()) lifestyle outside dedicated workouts")
        }

        if let t = tdee {
            parts.append(String(format: "estimated daily calorie need ~%.0f kcal", t))
        }

        if let p = proteinTargetG {
            parts.append("protein target ~\(p)g/day")
        }

        return parts.isEmpty ? "" : "User profile: \(parts.joined(separator: ", "))."
    }
}
