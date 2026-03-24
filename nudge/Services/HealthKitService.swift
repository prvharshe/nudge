import HealthKit

// MARK: - User goal

enum UserGoal: String, CaseIterable {
    case loseWeight   = "lose_weight"
    case buildMuscle  = "build_muscle"
    case endurance    = "improve_endurance"
    case stayActive   = "stay_active"
    case feelBetter   = "feel_better"

    var emoji: String {
        switch self {
        case .loseWeight:  return "🔥"
        case .buildMuscle: return "💪"
        case .endurance:   return "🏃"
        case .stayActive:  return "⚡"
        case .feelBetter:  return "😌"
        }
    }

    var title: String {
        switch self {
        case .loseWeight:  return "Lose weight"
        case .buildMuscle: return "Build muscle"
        case .endurance:   return "Improve endurance"
        case .stayActive:  return "Stay active"
        case .feelBetter:  return "Feel better"
        }
    }

    var subtitle: String {
        switch self {
        case .loseWeight:  return "Burn fat and feel lighter"
        case .buildMuscle: return "Get stronger and gain lean mass"
        case .endurance:   return "Run farther, breathe easier"
        case .stayActive:  return "Build a consistent movement habit"
        case .feelBetter:  return "More energy and less stress"
        }
    }

    var groqLabel: String {
        switch self {
        case .loseWeight:  return "lose weight and burn fat"
        case .buildMuscle: return "build muscle and get stronger"
        case .endurance:   return "improve endurance and cardiovascular fitness"
        case .stayActive:  return "stay consistently active and build a movement habit"
        case .feelBetter:  return "feel better overall — more energy, less stress"
        }
    }
}

// MARK: - Day statistics (for history detail + sync enrichment)

struct DayStats {
    let steps: Int
    let workoutMinutes: Int?    // nil if no workout recorded
    let calories: Int?           // active calories burned during workout
    let workoutType: String?     // e.g. "Outdoor Run"
    let sleepHours: Double?     // total sleep the night before
    let restingHR: Int?          // resting heart rate in BPM
    let hrv: Int?                // HRV SDNN in milliseconds
    // Nutrition (from Health app — e.g. Bevel, MyFitnessPal)
    let foodCalories: Int?       // dietary energy consumed
    let protein: Int?            // grams
    let carbs: Int?              // grams
    let fat: Int?                // grams
}

// MARK: - HealthKit detection result

struct HealthDetection {
    /// Whether HealthKit data suggests the user moved today
    let didMove: Bool
    /// Best matching activity tag ("walk", "run") or nil if only step-based
    let activityTag: String?
    /// Human-readable summary for the UI banner e.g. "outdoor run detected"
    let summary: String
}

// MARK: - HealthKitService

final class HealthKitService {

    static let shared = HealthKitService()
    private let store = HKHealthStore()

    // Step threshold below which we don't count as "moved"
    private let stepThreshold: Double = 4_000

    // Types we want to read
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned,
            .restingHeartRate, .heartRateVariabilitySDNN,
            .dietaryEnergyConsumed, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal
        ]
        for id in quantityIDs {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    // MARK: - Authorization

    /// Returns true if authorization was granted (or already granted).
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Today detection

    /// Checks workouts first, falls back to step count.
    /// Returns nil if HealthKit is unavailable or the user denied access.
    func detectToday() async -> HealthDetection? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        // Try workouts first — they're richer
        if let detection = await detectFromWorkouts() {
            return detection
        }

        // Fall back to step count
        return await detectFromSteps()
    }

    // MARK: - Workout query

    private func detectFromWorkouts() async -> HealthDetection? {
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: .now),
            end: .now,
            options: .strictStartDate
        )
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 10,
                sortDescriptors: [sortDesc]
            ) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                // Pick the most significant workout
                let best = workouts.max { a, b in
                    a.duration < b.duration
                } ?? workouts[0]

                let (tag, label) = Self.classify(best.workoutActivityType)
                continuation.resume(returning: HealthDetection(
                    didMove: true,
                    activityTag: tag,
                    summary: label
                ))
            }
            store.execute(query)
        }
    }

    // MARK: - Step count query

    private func detectFromSteps() async -> HealthDetection? {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: .now),
            end: .now,
            options: .strictStartDate
        )
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                guard let sum = stats?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                let steps = sum.doubleValue(for: .count())
                guard steps >= self.stepThreshold else {
                    continuation.resume(returning: HealthDetection(
                        didMove: false,
                        activityTag: nil,
                        summary: "\(Int(steps)) steps today"
                    ))
                    return
                }
                continuation.resume(returning: HealthDetection(
                    didMove: true,
                    activityTag: "walk",
                    summary: "\(Int(steps).formatted()) steps detected"
                ))
            }
            store.execute(query)
        }
    }

    // MARK: - Full day stats (for history detail + sync)

    /// Fetches step count, workout, sleep, resting HR and HRV for any given date.
    func fetchStats(for date: Date) async -> DayStats? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        async let steps   = fetchSteps(from: start, to: end)
        async let workout = fetchBestWorkout(from: start, to: end)
        async let sleep   = fetchSleep(forNightBefore: date)
        // Use day-scoped averages so each history entry shows its own HR/HRV
        async let hr      = fetchDailyQuantity(.restingHeartRate,
                                               unit: .count().unitDivided(by: .minute()),
                                               from: start, to: end)
        async let hrv     = fetchDailyQuantity(.heartRateVariabilitySDNN,
                                               unit: .secondUnit(with: .milli),
                                               from: start, to: end)
        async let foodCal  = fetchNutritionSum(.dietaryEnergyConsumed, unit: .kilocalorie(), from: start, to: end)
        async let prot     = fetchNutritionSum(.dietaryProtein, unit: .gram(), from: start, to: end)
        async let carbsVal = fetchNutritionSum(.dietaryCarbohydrates, unit: .gram(), from: start, to: end)
        async let fatVal   = fetchNutritionSum(.dietaryFatTotal, unit: .gram(), from: start, to: end)

        let stepCount   = await steps
        let bestWorkout = await workout
        let sleepHours  = await sleep
        let restingHR   = await hr.map { Int($0) }
        let hrvMs       = await hrv.map { Int($0) }
        let foodCalories = await foodCal.map { Int($0) }
        let proteinG     = await prot.map { Int($0) }
        let carbsG       = await carbsVal.map { Int($0) }
        let fatG         = await fatVal.map { Int($0) }

        var workoutMinutes: Int? = nil
        var calories: Int? = nil
        var workoutType: String? = nil

        if let w = bestWorkout {
            workoutMinutes = Int(w.duration / 60)
            workoutType = Self.workoutTypeName(w.workoutActivityType)
            if let cal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()) {
                calories = Int(cal)
            }
        }

        return DayStats(
            steps: stepCount,
            workoutMinutes: workoutMinutes,
            calories: calories,
            workoutType: workoutType,
            sleepHours: sleepHours,
            restingHR: restingHR,
            hrv: hrvMs,
            foodCalories: foodCalories,
            protein: proteinG,
            carbs: carbsG,
            fat: fatG
        )
    }

    // MARK: - Current recovery signal (for morning nudge)

    /// Returns today's resting HR and HRV, searching the past 48 h if today has no data yet.
    func fetchCurrentRecovery() async -> (restingHR: Int?, hrv: Int?) {
        guard HKHealthStore.isHealthDataAvailable() else { return (nil, nil) }
        let since = Date().addingTimeInterval(-48 * 3600)
        async let hr  = fetchLatestQuantity(.restingHeartRate,
                                            unit: HKUnit.count().unitDivided(by: .minute()),
                                            since: since)
        async let hrv = fetchLatestQuantity(.heartRateVariabilitySDNN,
                                            unit: HKUnit.secondUnit(with: .milli),
                                            since: since)
        return (await hr.map { Int($0) }, await hrv.map { Int($0) })
    }

    // MARK: - Per-day average quantity (for history — scoped strictly to that calendar day)

    private func fetchDailyQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    // MARK: - Nutrition sum (dietary data logged in Health app)

    private func fetchNutritionSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            self.store.execute(query)
        }
    }

    // MARK: - Latest quantity helper (for live recovery signal — searches a broad window)

    private func fetchLatestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since: Date
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            self.store.execute(query)
        }
    }

    // MARK: - Sleep query

    /// Returns total hours of sleep for the night *before* the given date.
    /// Window: 8 pm the previous evening → 11 am the given morning.
    private func fetchSleep(forNightBefore date: Date) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        // 16 hours before midnight = 8 pm the prior evening
        guard let windowStart = cal.date(byAdding: .hour, value: -16, to: dayStart),
              let windowEnd   = cal.date(byAdding: .hour, value:  11, to: dayStart) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Count actual sleep stages (not inBed or awake)
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]

                let asleep = samples.filter { asleepValues.contains($0.value) }
                guard !asleep.isEmpty else { continuation.resume(returning: nil); return }

                // Merge overlapping intervals (different sources can overlap)
                var intervals = asleep.map { ($0.startDate, $0.endDate) }
                intervals.sort { $0.0 < $1.0 }

                var merged: [(Date, Date)] = [intervals[0]]
                for iv in intervals.dropFirst() {
                    let last = merged[merged.count - 1]
                    if iv.0 <= last.1 {
                        merged[merged.count - 1] = (last.0, max(last.1, iv.1))
                    } else {
                        merged.append(iv)
                    }
                }

                let totalSeconds = merged.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) }
                let hours = totalSeconds / 3600
                // Sanity-check: ignore anything under 30 min or over 14 hours
                continuation.resume(returning: (0.5...14).contains(hours) ? hours : nil)
            }
            self.store.execute(query)
        }
    }

    private func fetchSteps(from start: Date, to end: Date) async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                let count = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(count))
            }
            store.execute(query)
        }
    }

    private func fetchBestWorkout(from start: Date, to end: Date) async -> HKWorkout? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDesc = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 10,
                sortDescriptors: [sortDesc]
            ) { _, samples, _ in
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts.max { $0.duration < $1.duration })
            }
            store.execute(query)
        }
    }

    // MARK: - Weekly step counts (for 7-day chart)

    /// Returns step counts for each of the last 7 calendar days, oldest first.
    func fetchWeeklySteps() async -> [(date: Date, steps: Int)] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let cal = Calendar.current
        let now = Date.now
        let anchorDate = cal.startOfDay(for: now)
        guard let sevenDaysAgo = cal.date(byAdding: .day, value: -6, to: anchorDate) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: now, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                guard let collection = results else { continuation.resume(returning: []); return }
                var output: [(Date, Int)] = []
                collection.enumerateStatistics(from: sevenDaysAgo, to: now) { stats, _ in
                    let count = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    output.append((stats.startDate, Int(count)))
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }

    // MARK: - Trend data (for Trends tab)

    /// Daily step totals for the last `days` calendar days, oldest-first.
    func fetchStepHistory(days: Int) async -> [(date: Date, steps: Int)] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: anchor) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                guard let col = results else { continuation.resume(returning: []); return }
                var out: [(Date, Int)] = []
                col.enumerateStatistics(from: start, to: .now) { stats, _ in
                    let count = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    out.append((stats.startDate, Int(count)))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Daily average resting heart rate for the last `days` days, oldest-first.
    func fetchRHRHistory(days: Int) async -> [(date: Date, rhr: Int)] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return [] }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: anchor) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                guard let col = results else { continuation.resume(returning: []); return }
                var out: [(Date, Int)] = []
                col.enumerateStatistics(from: start, to: .now) { stats, _ in
                    if let avg = stats.averageQuantity()?.doubleValue(for: unit) {
                        out.append((stats.startDate, Int(avg)))
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Total sleep per wake-day for the last `days` days, batch-fetched in one query.
    func fetchSleepHistory(days: Int) async -> [(date: Date, hours: Double)] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .day, value: -days, to: dayStart) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: .now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                // Group intervals by wake day (end date's calendar day)
                var byDay: [Date: [(Date, Date)]] = [:]
                for s in samples where asleepValues.contains(s.value) {
                    let wakeDay = cal.startOfDay(for: s.endDate)
                    byDay[wakeDay, default: []].append((s.startDate, s.endDate))
                }
                var out: [(Date, Double)] = []
                for (day, intervals) in byDay {
                    var sorted = intervals.sorted { $0.0 < $1.0 }
                    var merged: [(Date, Date)] = [sorted[0]]
                    for iv in sorted.dropFirst() {
                        let last = merged[merged.count - 1]
                        if iv.0 <= last.1 { merged[merged.count - 1] = (last.0, max(last.1, iv.1)) }
                        else { merged.append(iv) }
                    }
                    let h = merged.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) } / 3600
                    if (0.5...14).contains(h) { out.append((day, h)) }
                }
                continuation.resume(returning: out.sorted { $0.0 < $1.0 })
            }
            self.store.execute(query)
        }
    }

    /// Average daily macros over the last `days` days (only counts days with logged data).
    func fetchNutritionAverages(days: Int) async -> (kcal: Int?, protein: Int?, carbs: Int?, fat: Int?) {
        guard HKHealthStore.isHealthDataAvailable() else { return (nil, nil, nil, nil) }
        async let kcalV  = fetchDailyMacroValues(.dietaryEnergyConsumed, unit: .kilocalorie(), days: days)
        async let protV  = fetchDailyMacroValues(.dietaryProtein,        unit: .gram(),        days: days)
        async let carbsV = fetchDailyMacroValues(.dietaryCarbohydrates,  unit: .gram(),        days: days)
        async let fatV   = fetchDailyMacroValues(.dietaryFatTotal,       unit: .gram(),        days: days)
        func avg(_ vals: [Double]) -> Int? {
            let nonZero = vals.filter { $0 > 0 }
            return nonZero.isEmpty ? nil : Int(nonZero.reduce(0, +) / Double(nonZero.count))
        }
        return (avg(await kcalV), avg(await protV), avg(await carbsV), avg(await fatV))
    }

    private func fetchDailyMacroValues(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int
    ) async -> [Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -days, to: anchor) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: pred,
                options: .cumulativeSum, anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                guard let col = results else { continuation.resume(returning: []); return }
                var vals: [Double] = []
                col.enumerateStatistics(from: start, to: .now) { stats, _ in
                    if let v = stats.sumQuantity()?.doubleValue(for: unit) { vals.append(v) }
                }
                continuation.resume(returning: vals)
            }
            self.store.execute(query)
        }
    }

    // MARK: - Unlogged moved days (for auto-fill prompt)

    /// Returns dates (up to `lookback` days back) where HK shows movement but no Entry was logged.
    func findUnloggedMovedDays(lookback: Int, loggedDates: Set<Date>) async -> [Date] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var result: [Date] = []

        for offset in 1...lookback {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            guard !loggedDates.contains(day) else { continue }

            let end = cal.date(byAdding: .day, value: 1, to: day) ?? day
            async let steps = fetchSteps(from: day, to: end)
            async let workout = fetchBestWorkout(from: day, to: end)

            let s = await steps
            let w = await workout
            if s >= Int(stepThreshold) || w != nil {
                result.append(day)
            }
        }
        return result
    }

    // MARK: - Workout type → app tag

    static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running, .trackAndField:          return "Outdoor Run"
        case .walking:                           return "Walk"
        case .hiking:                            return "Hike"
        case .cycling, .handCycling:             return "Ride"
        case .swimming, .swimBikeRun:            return "Swim"
        case .yoga, .mindAndBody, .pilates:      return "Yoga"
        case .highIntensityIntervalTraining:     return "HIIT"
        case .functionalStrengthTraining,
             .traditionalStrengthTraining:       return "Strength Training"
        case .crossTraining:                     return "Cross Training"
        case .dance, .barre, .kickboxing:        return "Dance"
        default:                                  return "Workout"
        }
    }

    private static func classify(_ type: HKWorkoutActivityType) -> (tag: String?, label: String) {
        switch type {
        case .running, .trackAndField:
            return ("run", "run detected")
        case .walking, .hiking:
            return ("walk", "walk detected")
        case .cycling, .handCycling:
            return ("walk", "ride detected")
        case .swimming, .swimBikeRun:
            return ("run", "swim detected")
        case .yoga, .mindAndBody, .pilates:
            return ("walk", "yoga session detected")
        case .highIntensityIntervalTraining, .functionalStrengthTraining,
             .traditionalStrengthTraining, .crossTraining:
            return ("run", "workout detected")
        case .dance, .barre, .kickboxing:
            return ("run", "dance session detected")
        default:
            return (nil, "activity detected")
        }
    }
}
