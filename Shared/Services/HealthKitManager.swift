//
//  HealthKitManager.swift
//  NALI Migraine Log
//
//  Bidirectional HealthKit bridge:
//
//  • READS sleep, HRV, resting heart rate, step count, and menstrual cycle
//    samples to feed `MigrainePredictionService`'s feature extractor.
//
//  • WRITES the user's logged migraines back to Apple Health as `.headache`
//    category samples (iOS 17+ / watchOS 10+) so they show up in the system
//    Health app under Browse → Symptoms → Headache and are available to
//    third-party apps the user has granted access to (sleep apps, fitness
//    apps, clinical tools). Pain level is mapped to `HKCategoryValueSeverity`
//    via `severityValue(forPainLevel:)`.
//
//  Mirroring is OPT-IN. The `isHealthSyncEnabled` UserDefaults flag (default
//  false) governs whether `MigraineViewModel.addMigraine`/`updateMigraine`/
//  `deleteMigraine` will fan out to Health. Toggling it from the Settings
//  screen flips the flag; the user can also revoke at any time from the
//  system Health app's Sources → Headway pane (which is what Apple expects
//  to be the primary revoke surface).
//
//  Each migraine carries `HKMetadataKeyExternalUUID = migraine.id` on its
//  Health sample so we can find-and-replace cleanly on edit, and find-and-
//  delete cleanly when the user removes the entry from Headway. This means
//  re-running mirror operations is idempotent — backfills don't duplicate.
//
//  All data stays on the user's device + iCloud account; nothing is sent to
//  any developer-side server. Apple's HealthKit "All Health Data" entitlement
//  (`com.apple.developer.healthkit`) covers both read and write — there is
//  no separate "write" entitlement to add.
//

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
import CoreData

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    /// UserDefaults key driving whether new/updated/deleted migraines are
    /// mirrored into Apple Health. Default is `false` — opt-in only.
    private static let healthSyncEnabledKey = "healthkit.syncMigrainesEnabled"

    @Published var isAuthorized = false
    @Published var lastError: Error?
    @Published var latestSnapshot: HealthKitSnapshot?

    /// Whether the user has opted in to mirroring their migraines to Apple
    /// Health. Backed by `UserDefaults`. Reading this is fast; setting it
    /// publishes via `objectWillChange` so the Settings toggle stays in
    /// sync with the underlying flag.
    @Published var isHealthSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHealthSyncEnabled, forKey: Self.healthSyncEnabledKey)
            AppLogger.health.notice("Health sync \(self.isHealthSyncEnabled ? "enabled" : "disabled", privacy: .public)")
        }
    }

    #if canImport(HealthKit)
    private let healthStore: HKHealthStore?
    #endif
    private let calendar = Calendar.current
    
    /// Whether HealthKit is available on this device.
    var isAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }
    
    private init() {
        self.isHealthSyncEnabled = UserDefaults.standard.bool(forKey: Self.healthSyncEnabledKey)

        #if canImport(HealthKit)
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        } else {
            healthStore = nil
        }
        #endif
    }
    
    // MARK: - Authorization
    
    /// Request HealthKit read + (where supported) write permissions.
    ///
    /// Write access for the `.headache` type is only available on iOS 17 /
    /// watchOS 10 and later. On older OS versions we ask for reads only and
    /// silently leave the mirroring path disabled — `writeMigraineToHealth`
    /// gates on the same availability check.
    func requestAuthorization() async {
        #if canImport(HealthKit)
        guard let healthStore = healthStore else {
            lastError = HealthKitError.notAvailable
            return
        }
        
        let toShare: Set<HKSampleType>
        if #available(iOS 17.0, watchOS 10.0, *) {
            toShare = writeTypes
        } else {
            toShare = []
        }

        do {
            try await healthStore.requestAuthorization(toShare: toShare, read: readTypes)
            isAuthorized = true
            AppLogger.health.notice("HealthKit authorization granted (write types: \(toShare.count, privacy: .public))")
        } catch {
            lastError = error
            isAuthorized = false
            AppLogger.health.error("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        #else
        lastError = HealthKitError.notAvailable
        #endif
    }
    
    // MARK: - Data Fetching
    
    /// Fetch all health data into a snapshot for the prediction engine.
    func fetchSnapshot() async -> HealthKitSnapshot {
        var snapshot = HealthKitSnapshot()
        
        #if canImport(HealthKit)
        guard healthStore != nil, isAuthorized else {
            return snapshot
        }
        
        // Fetch all concurrently
        async let sleep = getLastNightSleep()
        async let hrv = getLatestHRV()
        async let rhr = getRestingHeartRate()
        async let steps = getStepsYesterday()
        async let menstrual = getDaysSinceMenstruation()
        
        snapshot.sleepHours = await sleep
        snapshot.hrv = await hrv
        snapshot.restingHeartRate = await rhr
        snapshot.steps = await steps
        snapshot.daysSinceMenstruation = await menstrual
        
        latestSnapshot = snapshot
        #endif
        return snapshot
    }
    
    // MARK: - HealthKit Queries
    
    #if canImport(HealthKit)
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let rhr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(rhr)
        }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let menstrual = HKObjectType.categoryType(forIdentifier: .menstrualFlow) {
            types.insert(menstrual)
        }

        // We also read back our own headache samples to dedupe writes during
        // the backfill / re-edit paths. Without read access on the headache
        // type we couldn't query existing samples by ExternalUUID before
        // re-writing, which would leak duplicates on every edit. Only added
        // on platforms where the type exists.
        if #available(iOS 17.0, watchOS 10.0, *) {
            if let headache = HKObjectType.categoryType(forIdentifier: .headache) {
                types.insert(headache)
            }
        }

        return types
    }

    /// Sample types we write to. Currently just the `.headache` category
    /// (iOS 17+ / watchOS 10+). Kept as a computed property — and gated
    /// behind `@available` at the call site — so the symbol is omitted
    /// entirely on older OS versions rather than being a runtime-empty set.
    @available(iOS 17.0, watchOS 10.0, *)
    private var writeTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if let headache = HKObjectType.categoryType(forIdentifier: .headache) {
            types.insert(headache)
        }
        return types
    }
    
    /// Total hours of sleep last night (between 6 PM yesterday and noon today).
    private func getLastNightSleep() async -> Double? {
        guard let healthStore = healthStore,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }
        
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: startOfToday)! // 6 PM yesterday
        let sleepWindowEnd = calendar.date(byAdding: .hour, value: 12, to: startOfToday)!  // noon today
        
        let predicate = HKQuery.predicateForSamples(
            withStart: sleepWindowStart,
            end: sleepWindowEnd,
            options: .strictStartDate
        )
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            
            // Sum up asleep intervals (exclude "inBed" which is HKCategoryValueSleepAnalysis.inBed = 0)
            var totalSleep: TimeInterval = 0
            for sample in samples {
                // Values > 0 represent actual sleep stages (asleep, deep, REM, core)
                if sample.value > 0 {
                    totalSleep += sample.endDate.timeIntervalSince(sample.startDate)
                }
            }
            
            let hours = totalSleep / 3600.0
            return hours > 0 ? hours : nil
        } catch {
            AppLogger.health.error("HealthKit sleep fetch error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    /// Latest HRV value (SDNN in ms).
    private func getLatestHRV() async -> Double? {
        guard let healthStore = healthStore,
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return nil
        }
        
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let predicate = HKQuery.predicateForSamples(
            withStart: yesterday,
            end: Date(),
            options: .strictStartDate
        )
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrvType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            return samples.first?.quantity.doubleValue(for: .secondUnit(with: .milli))
        } catch {
            AppLogger.health.error("HealthKit HRV fetch error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    /// Latest resting heart rate (BPM).
    private func getRestingHeartRate() async -> Double? {
        guard let healthStore = healthStore,
              let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return nil
        }
        
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date())!
        let predicate = HKQuery.predicateForSamples(
            withStart: twoDaysAgo,
            end: Date(),
            options: .strictStartDate
        )
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: rhrType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            return samples.first?.quantity.doubleValue(for: bpmUnit)
        } catch {
            AppLogger.health.error("HealthKit RHR fetch error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    /// Total step count for yesterday.
    private func getStepsYesterday() async -> Int? {
        guard let healthStore = healthStore,
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }
        
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfYesterday,
            end: startOfToday,
            options: .strictStartDate
        )
        
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: stepsType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    continuation.resume(returning: steps)
                }
                healthStore.execute(query)
            }
            return result > 0 ? Int(result) : nil
        } catch {
            AppLogger.health.error("HealthKit steps fetch error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    /// Days since last recorded menstrual flow. Returns nil if no data.
    private func getDaysSinceMenstruation() async -> Int? {
        guard let healthStore = healthStore,
              let menstrualType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return nil
        }
        
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: Date())!
        let predicate = HKQuery.predicateForSamples(
            withStart: sixtyDaysAgo,
            end: Date(),
            options: .strictStartDate
        )
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: menstrualType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            guard let lastFlow = samples.first else { return nil }
            return calendar.dateComponents([.day], from: lastFlow.startDate, to: Date()).day
        } catch {
            AppLogger.health.error("HealthKit menstrual fetch error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Historical fetches (for analytics correlations)
    //
    // These differ from the snapshot fetchers above in two ways:
    //   • they accept an explicit window rather than always reading "last
    //     night" / "yesterday", so the Analytics dashboard can correlate
    //     migraines with the matching sleep/HRV samples; and
    //   • they return arrays of timestamped samples rather than a single
    //     scalar, so views can plot a time series with migraine markers.
    //
    // All methods no-op (return []) when HealthKit is unavailable or the
    // user hasn't granted authorization — the same defensive pattern used
    // by the snapshot fetchers.
    
    /// Per-night total sleep hours over the supplied window. Each night is
    /// keyed by the calendar morning it ended on, so "the night before
    /// Monday May 5" returns a sample with `night = May 5 00:00`.
    ///
    /// The query window for each night is 6 PM the previous day → noon
    /// of the keyed day, matching `getLastNightSleep()`'s definition.
    /// Nights without any logged "asleep" samples are omitted.
    func fetchSleepHoursPerNight(in interval: DateInterval) async -> [SleepNightSample] {
        #if canImport(HealthKit)
        guard let healthStore = healthStore, isAuthorized else { return [] }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: calendar.date(byAdding: .hour, value: -6, to: interval.start) ?? interval.start,
            end: calendar.date(byAdding: .hour, value: 12, to: interval.end) ?? interval.end,
            options: .strictStartDate
        )
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            
            var totals: [Date: TimeInterval] = [:]
            for sample in samples {
                guard sample.value > 0 else { continue }
                let nightKey = nightKey(forSampleEndingAt: sample.endDate)
                totals[nightKey, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
            }
            
            return totals
                .filter { $0.value > 0 }
                .map { SleepNightSample(night: $0.key, hours: $0.value / 3600.0) }
                .sorted { $0.night < $1.night }
        } catch {
            AppLogger.health.error("HealthKit historical sleep fetch error: \(error.localizedDescription, privacy: .public)")
            return []
        }
        #else
        return []
        #endif
    }
    
    /// Menstrual-flow events recorded inside the supplied window. Each
    /// returned event represents a single sample (one calendar day in
    /// HealthKit's data model). The cycle-phase analytics treat the
    /// *first* event of each cycle as the period start — `MenstrualEvent`
    /// includes a precomputed `isCycleStart` flag so callers don't have
    /// to re-derive the gap analysis.
    ///
    /// We deliberately do NOT gate this on `HKBiologicalSex` —
    /// menstrual tracking in Apple Health is exposed to all users, and
    /// the migraine correlation card on the dashboard appears only when
    /// real samples exist (data-driven gating, not identity-driven).
    func fetchMenstrualEvents(in interval: DateInterval) async -> [MenstrualEvent] {
        #if canImport(HealthKit)
        guard let healthStore = healthStore, isAuthorized else { return [] }
        guard let menstrualType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return []
        }
        
        // Pad the start so a flow event that began before the window
        // but spans into it can still anchor a cycle day calculation.
        let paddedStart = calendar.date(byAdding: .day, value: -45, to: interval.start) ?? interval.start
        let predicate = HKQuery.predicateForSamples(
            withStart: paddedStart,
            end: interval.end,
            options: .strictStartDate
        )
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: menstrualType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            // HealthKit records a sample per logged day; "cycle start"
            // = the first day after a gap of ≥ 2 calendar days. We
            // pre-tag the events so the analytics layer doesn't have
            // to redo the gap analysis on every render.
            var events: [MenstrualEvent] = []
            var lastDay: Date?
            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                let isStart: Bool = {
                    guard let last = lastDay else { return true }
                    let gapDays = calendar.dateComponents([.day], from: last, to: day).day ?? 0
                    return gapDays >= 2
                }()
                events.append(MenstrualEvent(date: day, isCycleStart: isStart))
                lastDay = day
            }
            return events
        } catch {
            AppLogger.health.error("HealthKit menstrual history fetch error: \(error.localizedDescription, privacy: .public)")
            return []
        }
        #else
        return []
        #endif
    }
    
    /// True when the user has logged at least one menstrual-flow sample
    /// in the past 365 days. Used to gate the cycle-phase correlation
    /// card on the Analytics dashboard (data-driven, not gender-driven).
    /// Cheap because we cap the limit at 1 — the query short-circuits
    /// after the first match.
    func hasAnyMenstrualHistory() async -> Bool {
        #if canImport(HealthKit)
        guard let healthStore = healthStore, isAuthorized else { return false }
        guard let menstrualType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return false
        }
        
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: yearAgo,
            end: Date(),
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: menstrualType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            return !samples.isEmpty
        } catch {
            AppLogger.health.error("HealthKit menstrual probe error: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        return false
        #endif
    }
    
    /// All HRV-SDNN samples (in milliseconds) recorded inside the supplied
    /// window. Returned in chronological order — callers are expected to
    /// downsample (rolling average, daily median, etc.) for plotting.
    func fetchHRVSamples(in interval: DateInterval) async -> [HRVPoint] {
        #if canImport(HealthKit)
        guard let healthStore = healthStore, isAuthorized else { return [] }
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictStartDate
        )
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrvType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        
        do {
            let samples = try await descriptor.result(for: healthStore)
            let unit = HKUnit.secondUnit(with: .milli)
            return samples.map { HRVPoint(date: $0.startDate, valueMs: $0.quantity.doubleValue(for: unit)) }
        } catch {
            AppLogger.health.error("HealthKit historical HRV fetch error: \(error.localizedDescription, privacy: .public)")
            return []
        }
        #else
        return []
        #endif
    }
    
    /// Map a sleep sample's `endDate` onto the calendar morning we
    /// attribute the night to. End times after noon spill over to the
    /// next day — fine for matching against migraines the same morning,
    /// less useful for night-shift workers (acceptable tradeoff for v1).
    private func nightKey(forSampleEndingAt end: Date) -> Date {
        let dayStart = calendar.startOfDay(for: end)
        let hour = calendar.component(.hour, from: end)
        if hour < 12 {
            return dayStart
        } else {
            return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        }
    }
    
    // MARK: - Writing migraines back to Health
    //
    // The flow is always: delete-by-UUID → write-fresh. This keeps edits
    // idempotent and avoids accumulating stale samples when the user changes
    // a migraine's pain level or duration. Every method here no-ops cleanly
    // when the device doesn't support HealthKit or when the user hasn't
    // authorized writes — failures are logged but never surfaced as fatal.

    /// Write the given migraine to Apple Health as a `.headache` sample,
    /// replacing any prior sample we already wrote for the same migraine.
    ///
    /// Safe to call from any caller — does nothing when:
    ///   • HealthKit isn't available on the device
    ///   • the user hasn't enabled `isHealthSyncEnabled`
    ///   • the OS version is below iOS 17 / watchOS 10
    ///   • the migraine is missing `id` or `startTime`
    @available(iOS 17.0, watchOS 10.0, *)
    func writeMigraineToHealth(_ migraine: MigraineEvent) async {
        #if canImport(HealthKit)
        guard isHealthSyncEnabled, isAuthorized else { return }
        guard let healthStore = healthStore else { return }
        guard let headacheType = HKObjectType.categoryType(forIdentifier: .headache) else {
            AppLogger.health.error("Headache category type not available on this OS")
            return
        }
        guard let migraineID = migraine.id?.uuidString,
              let startTime = migraine.startTime else {
            AppLogger.health.error("Migraine missing id or startTime; skipping Health write")
            return
        }

        // Headache samples must have endDate >= startDate. If the user
        // hasn't set an end time yet (still ongoing), use startTime — this
        // produces a zero-duration sample that Apple Health treats as a
        // point-in-time event, which we'll widen on the next edit once
        // the user records when it ended.
        let endTime = migraine.endTime ?? startTime
        let severity = severityValue(forPainLevel: Int(migraine.painLevel))

        do {
            try await deleteHealthSamples(forMigraineUUID: migraineID)

            let sample = HKCategorySample(
                type: headacheType,
                value: severity,
                start: startTime,
                end: endTime,
                metadata: [
                    HKMetadataKeyExternalUUID: migraineID,
                ]
            )

            try await healthStore.save(sample)
            AppLogger.health.notice("Wrote migraine to Health: \(migraineID, privacy: .public) severity=\(severity, privacy: .public)")
        } catch {
            AppLogger.health.error("Failed to write migraine to Health: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Delete every Health sample we previously wrote for the given migraine
    /// id. Called on its own when the user deletes a migraine in Headway,
    /// and as the first step of `writeMigraineToHealth` for edits.
    @available(iOS 17.0, watchOS 10.0, *)
    func deleteHealthSamples(forMigraineUUID uuid: String) async throws {
        #if canImport(HealthKit)
        guard let healthStore = healthStore,
              let headacheType = HKObjectType.categoryType(forIdentifier: .headache) else {
            return
        }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: uuid
        )

        // `deleteObjects(of:predicate:)` returns the number of samples
        // removed. We don't surface that — the caller doesn't care, and the
        // common case is 0 (no prior write) or 1 (one prior write).
        _ = try await healthStore.deleteObjects(of: headacheType, predicate: predicate)
        #endif
    }

    /// Convenience entry point used when the user *deletes* a migraine in
    /// Headway. Mirrors the deletion into Health if mirroring is enabled
    /// and the user has authorized writes. Errors are swallowed and logged
    /// — a Health-side failure should never block the Core Data delete.
    @available(iOS 17.0, watchOS 10.0, *)
    func mirrorDeletion(ofMigraineUUID uuid: String) async {
        #if canImport(HealthKit)
        guard isHealthSyncEnabled, isAuthorized else { return }
        do {
            try await deleteHealthSamples(forMigraineUUID: uuid)
            AppLogger.health.notice("Mirrored migraine deletion to Health: \(uuid, privacy: .public)")
        } catch {
            AppLogger.health.error("Failed to mirror migraine deletion to Health: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Backfill every migraine in `migraines` to Apple Health. Idempotent —
    /// the per-migraine path already deletes any existing sample with a
    /// matching ExternalUUID before writing, so calling this repeatedly
    /// after partial failures will converge rather than duplicate.
    ///
    /// Returns `(written, failed)` so the caller can show a progress
    /// summary in the UI.
    @available(iOS 17.0, watchOS 10.0, *)
    @discardableResult
    func backfillMigrainesToHealth(_ migraines: [MigraineEvent]) async -> (written: Int, failed: Int) {
        #if canImport(HealthKit)
        guard isHealthSyncEnabled, isAuthorized else {
            AppLogger.health.notice("Backfill skipped: sync not enabled or not authorized")
            return (0, 0)
        }

        var written = 0
        var failed = 0
        for migraine in migraines {
            // Re-check on every iteration so the loop unwinds quickly if
            // the user toggles the flag off mid-backfill.
            guard isHealthSyncEnabled else { break }
            guard migraine.id != nil, migraine.startTime != nil else {
                failed += 1
                continue
            }
            await writeMigraineToHealth(migraine)
            written += 1
        }
        AppLogger.health.notice("Backfill complete: written=\(written, privacy: .public) failed=\(failed, privacy: .public)")
        return (written, failed)
        #else
        return (0, 0)
        #endif
    }

    /// Map our 1–10 pain scale into Apple's `HKCategoryValueSeverity`. The
    /// raw thresholds are deliberately conservative on the moderate/severe
    /// boundary — Apple's UI surfaces "Severe" with the same red emphasis
    /// it uses for emergency-level events, so we don't promote anything
    /// below 7 to that bucket.
    private func severityValue(forPainLevel level: Int) -> Int {
        #if canImport(HealthKit)
        switch level {
        case 1...3:  return HKCategoryValueSeverity.mild.rawValue
        case 4...6:  return HKCategoryValueSeverity.moderate.rawValue
        case 7...10: return HKCategoryValueSeverity.severe.rawValue
        default:     return HKCategoryValueSeverity.unspecified.rawValue
        }
        #else
        return 0
        #endif
    }
    #endif
}

// MARK: - Historical sample value types

/// One night of total sleep, used by the Analytics correlation views.
/// `night` is the calendar morning that the sleep ended on — i.e. the
/// "day of" sleep, the day a migraine logged that morning would
/// correlate with.
struct SleepNightSample: Identifiable, Hashable, Sendable {
    var id: Date { night }
    let night: Date
    let hours: Double
}

/// One HRV-SDNN reading from HealthKit, in milliseconds.
struct HRVPoint: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let valueMs: Double
}

/// One day of menstrual flow logged in HealthKit. `isCycleStart` is
/// pre-derived by the fetch (a sample that follows a ≥ 2-day gap is
/// treated as the start of a new cycle), so the analytics layer can
/// walk a list of these without re-doing the gap analysis.
struct MenstrualEvent: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let isCycleStart: Bool
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case queryFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .queryFailed(let detail):
            return "HealthKit query failed: \(detail)"
        }
    }
}
