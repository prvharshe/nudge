import SwiftUI

// MARK: - Metric Info Context (for sheet presentation)

struct MetricInfoContext: Identifiable {
    let id = UUID()
    let info: MetricInfo
    let rawValue: String
}

// MARK: - Metric Info

struct MetricInfo {
    let title: String
    let abbreviation: String
    let icon: String
    let iconColor: Color
    let what: String         // 2–3 sentences: what is this metric
    let why: String          // 1–2 sentences: why it matters
    let tips: [String]       // 3 actionable improvement tips
    let source: String       // attribution line
    var userInsight: ((String) -> String)?  // personalized sentence given raw value
}

// MARK: - Static factory methods (fact-checked content)

extension MetricInfo {

    // MARK: HRV

    static func hrv(value: Int) -> MetricInfo {
        MetricInfo(
            title: "Heart Rate Variability",
            abbreviation: "HRV",
            icon: "waveform.path.ecg",
            iconColor: Theme.blue,
            what: "HRV measures the millisecond variations between consecutive heartbeats. These fluctuations reflect your autonomic nervous system's balance — specifically how actively your parasympathetic (rest-and-digest) branch is working to counterbalance stress.",
            why: "Higher HRV generally signals better recovery, lower physiological stress, and greater cardiovascular adaptability. It's one of the earliest indicators of overtraining, illness, or sleep deprivation — often dropping 12–24 hours before you consciously feel off.",
            tips: [
                "A consistent sleep schedule stabilises HRV more than almost any other single factor",
                "Slow diaphragmatic breathing (5–6 breaths per minute) activates the vagus nerve and can raise HRV acutely",
                "Alcohol significantly suppresses HRV during sleep — even one drink affects the overnight reading"
            ],
            source: "American Heart Association · PLOS ONE (Electrophysiology)",
            userInsight: { v in
                let ms = Int(v) ?? 0
                switch ms {
                case ..<25:  return "Your reading of \(v)ms is on the lower end — this commonly reflects accumulated fatigue or acute stress. Prioritise recovery today."
                case 25..<45: return "Your reading of \(v)ms is moderate. Consistent sleep and aerobic exercise tend to raise HRV steadily over several weeks."
                case 45..<70: return "Your reading of \(v)ms is solid — this range is typical of healthy, active adults with good recovery habits."
                default:     return "Your reading of \(v)ms is excellent. This level is typical of well-trained athletes with strong and consistent recovery."
                }
            }
        )
    }

    // MARK: Resting HR

    static func restingHR(value: Int) -> MetricInfo {
        MetricInfo(
            title: "Resting Heart Rate",
            abbreviation: "RHR",
            icon: "heart.fill",
            iconColor: .red,
            what: "Your resting heart rate is how many times your heart beats per minute at complete rest. A lower RHR means your heart pumps more blood per beat — a marker of greater cardiac efficiency developed through regular aerobic training.",
            why: "The normal adult range is 60–100 BPM, but active adults commonly sit at 50–70. Chronically elevated RHR (>80) is associated with higher cardiovascular risk and often indicates insufficient recovery, dehydration, or prolonged stress.",
            tips: [
                "Regular moderate-intensity cardio (walking, cycling, swimming) lowers RHR more reliably than high-intensity exercise alone",
                "Dehydration can transiently raise RHR by 5–7 BPM — consistent hydration makes a measurable difference",
                "Chronic stress elevates RHR through sustained sympathetic activation — sleep quality and stress management both help"
            ],
            source: "Mayo Clinic · American Heart Association",
            userInsight: { v in
                let bpm = Int(v) ?? 0
                switch bpm {
                case ..<50:  return "\(v) BPM is athlete-level efficiency. Monitor for unusual upward trends, which can be an early sign of accumulated fatigue."
                case 50..<65: return "\(v) BPM reflects good cardiovascular fitness. Consistent aerobic activity is clearly paying off."
                case 65..<80: return "\(v) BPM is within the healthy range. Regular aerobic exercise will gradually lower this over weeks of consistent effort."
                default:     return "\(v) BPM is above the ideal zone. The most common causes — stress, poor sleep, and low activity — are all addressable."
                }
            }
        )
    }

    // MARK: Sleep

    static func sleep(value: Double) -> MetricInfo {
        MetricInfo(
            title: "Sleep Duration",
            abbreviation: "Sleep",
            icon: "moon.zzz.fill",
            iconColor: .indigo,
            what: "Sleep is your body's primary recovery mechanism. During deep (slow-wave) sleep, growth hormone is released to repair muscle tissue and consolidate physical adaptations. REM sleep processes emotional memory and restores cognitive function and mood regulation.",
            why: "Adults need 7–9 hours for full physical and cognitive recovery. Even one night below 6 hours measurably elevates cortisol, impairs insulin sensitivity, and reduces next-day exercise performance by 10–30%. Sleep debt accumulates and cannot be fully repaid with a single long night.",
            tips: [
                "A consistent wake time — even on weekends — is the single most powerful anchor for your circadian rhythm",
                "A cool bedroom (65–68°F / 18–20°C) significantly improves deep sleep quality and continuity",
                "Caffeine has a 5–7 hour half-life — a 3 pm coffee still has ~50% of its caffeine active at 8 pm"
            ],
            source: "National Sleep Foundation · NIH National Institute of Neurological Disorders",
            userInsight: { v in
                let hours = Double(v) ?? 0
                switch hours {
                case ..<5.5:  return "\(v)h is significantly below optimal. Research consistently links sleep under 6 hours with impaired recovery, elevated stress hormones, and reduced next-day performance."
                case 5.5..<7: return "\(v)h is below the 7–9 hour recommendation. You may be gradually accumulating mild sleep debt — watch for trends in your HRV and energy levels."
                case 7..<9:   return "\(v)h is in the optimal range. Your body has adequate time to complete all sleep cycles, including deep recovery sleep."
                default:      return "\(v)h is on the longer end. Consistently sleeping beyond 9 hours can sometimes signal underlying fatigue or recovery needs worth noting."
                }
            }
        )
    }

    // MARK: Steps

    static func steps(value: Int) -> MetricInfo {
        MetricInfo(
            title: "Daily Steps",
            abbreviation: "Steps",
            icon: "figure.walk",
            iconColor: Theme.green,
            what: "Daily step count measures NEAT — Non-Exercise Activity Thermogenesis. This is all the energy burned through movement that isn't formal exercise: walking, standing, fidgeting. NEAT can represent 15–50% of total daily energy expenditure depending on lifestyle.",
            why: "A landmark JAMA study found that 7,000+ steps per day is associated with 50–70% lower all-cause mortality compared to under 4,000. Steps beyond ~10,000 show diminishing health returns — consistency matters far more than chasing high numbers.",
            tips: [
                "Walking during phone calls adds 1,000–2,000 steps with zero extra time investment",
                "A 10-minute walk after meals improves blood glucose regulation and adds ~1,200 steps",
                "Hourly movement breaks (standing, short walks) contribute significantly to NEAT even on low-activity days"
            ],
            source: "JAMA Internal Medicine 2021 · CDC Physical Activity Guidelines for Americans",
            userInsight: { v in
                let n = Int(v) ?? 0
                switch n {
                case ..<4000:  return "\(v) steps is a low-activity day. A single 20-minute walk adds ~2,500 steps and has measurable cardiovascular and metabolic benefits."
                case 4000..<7000: return "\(v) steps is moderate. Research shows the biggest health benefit jump happens at ~7,000 steps/day."
                case 7000..<10000: return "\(v) steps hits the research-backed sweet spot most associated with reduced all-cause mortality risk."
                default:       return "\(v) steps is excellent. At this level you're achieving both cardiovascular and metabolic benefits well beyond baseline targets."
                }
            }
        )
    }

    // MARK: Protein

    static func protein(value: Int) -> MetricInfo {
        MetricInfo(
            title: "Dietary Protein",
            abbreviation: "Protein",
            icon: "fork.knife",
            iconColor: Theme.blue,
            what: "Protein is built from amino acids — the structural units your body uses to repair and build muscle fibres, synthesise enzymes and hormones, and maintain immune function. Unlike carbohydrates and fat, your body has no dedicated protein storage, making daily intake critical.",
            why: "For active adults, 1.6–2.2g per kilogram of bodyweight per day optimally supports muscle protein synthesis. How you distribute it matters too — spreading intake across 3–4 meals (20–40g each) triggers more total muscle-building response than the same amount in one or two sittings.",
            tips: [
                "Prioritise leucine-rich complete proteins — meat, fish, eggs, dairy, and soy contain all essential amino acids",
                "Post-exercise protein within 2 hours maximises the muscle protein synthesis window opened by training",
                "30g+ of protein at breakfast improves satiety signalling and reduces total daily caloric intake"
            ],
            source: "International Society of Sports Nutrition Position Stand · Journal of Physiology",
            userInsight: { v in
                let g = Int(v) ?? 0
                if g < 60 {
                    return "\(v)g is below the general minimum. At this level, muscle maintenance is difficult regardless of training — consider higher-protein foods at each meal."
                } else if g < 100 {
                    return "\(v)g is a baseline intake. Active adults generally benefit from targeting 1.6× or more of their bodyweight in kg to support muscle and recovery."
                } else {
                    return "\(v)g is a solid protein intake. Spread across 3–4 meals, you're maximising the muscle protein synthesis response throughout the day."
                }
            }
        )
    }

    // MARK: Calories (food)

    static func calories(value: Int) -> MetricInfo {
        MetricInfo(
            title: "Food Energy",
            abbreviation: "Calories",
            icon: "flame.fill",
            iconColor: .orange,
            what: "Dietary calories measure the energy your food provides. Your body uses this for everything from breathing and organ function (Basal Metabolic Rate) to exercise, digestion, and temperature regulation. Caloric balance — intake versus expenditure — is the primary driver of body weight change.",
            why: "Neither chronic undereating nor overeating is optimal for performance. Underfuelling (especially for active individuals) suppresses hormones, slows muscle recovery, and impairs cognitive function. The goal is matching intake to your actual energy needs — your TDEE estimate in Settings is a useful reference.",
            tips: [
                "Most people chronically underestimate intake by 20–40% — even rough tracking for 2 weeks builds accurate intuition",
                "Front-loading calories earlier in the day improves metabolic efficiency versus eating the same total late at night",
                "Highly processed foods are engineered to override satiety signals — whole foods make calorie balance effortless"
            ],
            source: "NIH Office of Dietary Supplements · USDA Dietary Guidelines for Americans",
            userInsight: { v in
                let kcal = Int(v) ?? 0
                if kcal < 1200 {
                    return "\(v) kcal is very low. Sustained intake below 1,200 kcal triggers metabolic adaptation and muscle catabolism even without exercise."
                } else if kcal < 1800 {
                    return "\(v) kcal is on the conservative side. Compare against your TDEE estimate in Settings to understand where you sit relative to your energy needs."
                } else {
                    return "\(v) kcal is a meaningful intake. Check how it aligns with your estimated daily need in Settings to understand your energy balance today."
                }
            }
        )
    }

    // MARK: Recovery Score

    static func recoveryScore(value: Int) -> MetricInfo {
        MetricInfo(
            title: "Recovery Score",
            abbreviation: "Readiness",
            icon: "bolt.heart.fill",
            iconColor: Theme.blue,
            what: "Your recovery score combines three physiological signals — sleep duration (40%), heart rate variability (30%), and resting heart rate (30%) — into a single 0–100 readiness number. It reflects how well your autonomic nervous system recovered overnight.",
            why: "Research shows that matching training intensity to daily readiness produces better long-term adaptations than following a fixed schedule regardless of how you feel. A high score means your body is primed for a quality session; a low score suggests backing off to avoid accumulated fatigue.",
            tips: [
                "Sleep quality carries the most weight at 40% — even 30 extra minutes of sleep can meaningfully shift your score",
                "Back-to-back intense training days without adequate recovery suppresses both HRV and score — rest days are physiologically productive",
                "Alcohol, acute stress, and early illness each independently suppress HRV and elevate RHR, compressing your score"
            ],
            source: "PLOS ONE · European Journal of Applied Physiology · Frontiers in Physiology",
            userInsight: { v in
                let n = Int(v) ?? 0
                switch n {
                case ..<35:  return "A score of \(v)/100 signals significant physiological stress. Your body is asking for recovery — light movement or full rest is the smartest choice today."
                case 35..<50: return "A score of \(v)/100 suggests your body is still working through recovery. Moderate activity is fine; avoid pushing intensity."
                case 50..<65: return "A score of \(v)/100 reflects decent recovery. Normal training intensity is appropriate — just listen to how you feel."
                case 65..<80: return "A score of \(v)/100 means your body is well-recovered and ready. A good day for a quality session."
                default:     return "A score of \(v)/100 is excellent — all three signals are aligned. A great day to make the most of your body's readiness."
                }
            }
        )
    }
}
