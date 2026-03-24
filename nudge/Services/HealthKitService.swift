import HealthKit

// MARK: - Day statistics (for history detail + sync enrichment)

struct DayStats {
    let steps: Int
    let workoutMinutes: Int?   // nil if no workout recorded
    let calories: Int?          // active calories, nil if unavailable
    let workoutType: String?    // e.g. "Outdoor Run"
    let sleepHours: Double?    // total sleep the night before, nil if unavailable
    let restingHR: Int?         // resting heart rate in BPM for that day
    let hrv: Int?               // HRV SDNN in milliseconds for that day
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
            .restingHeartRate, .heartRateVariabilitySDNN
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

        let stepCount   = await steps
        let bestWorkout = await workout
        let sleepHours  = await sleep
        let restingHR   = await hr.map { Int($0) }
        let hrvMs       = await hrv.map { Int($0) }

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
            hrv: hrvMs
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

    // MARK: - Per-day average quantity (for history — strictly scoped to that calendar day)

    /// Uses HKSampleQuery (not HKStatisticsQuery) so the date predicate is always honoured.
    private func fetchDailyQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let quantities = samples as? [HKQuantitySample], !quantities.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let total = quantities.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
                continuation.resume(returning: total / Double(quantities.count))
            }
            store.execute(query)
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
