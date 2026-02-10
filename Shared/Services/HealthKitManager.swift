//
//  HealthKitManager.swift
//  NALI Migraine Log
//
//  Reads health data from HealthKit for migraine prediction features:
//  sleep analysis, HRV, resting heart rate, step count, menstrual data.
//  All data stays on-device.
//

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    @Published var isAuthorized = false
    @Published var lastError: Error?
    @Published var latestSnapshot: HealthKitSnapshot?
    
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
        #if canImport(HealthKit)
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        } else {
            healthStore = nil
        }
        #endif
    }
    
    // MARK: - Authorization
    
    /// Request HealthKit read permissions.
    func requestAuthorization() async {
        #if canImport(HealthKit)
        guard let healthStore = healthStore else {
            lastError = HealthKitError.notAvailable
            return
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            print("✅ HealthKit authorization granted")
        } catch {
            lastError = error
            isAuthorized = false
            print("❌ HealthKit authorization failed: \(error.localizedDescription)")
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
            print("⚠️ HealthKit sleep fetch error: \(error.localizedDescription)")
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
            print("⚠️ HealthKit HRV fetch error: \(error.localizedDescription)")
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
            print("⚠️ HealthKit RHR fetch error: \(error.localizedDescription)")
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
            print("⚠️ HealthKit steps fetch error: \(error.localizedDescription)")
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
            print("⚠️ HealthKit menstrual fetch error: \(error.localizedDescription)")
            return nil
        }
    }
    #endif
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
