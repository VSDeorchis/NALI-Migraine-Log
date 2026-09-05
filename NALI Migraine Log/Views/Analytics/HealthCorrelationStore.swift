//
//  HealthCorrelationStore.swift
//  NALI Migraine Log
//
//  Loads historical sleep, HRV, and menstrual samples from HealthKit
//  (via the `HealthKitManager.fetch*` family) and produces the
//  comparison stats consumed by the Analytics dashboard:
//
//    • `sleepSummary`         — average sleep hours on the night before
//      a migraine vs. all other nights.
//    • `hrvSummary`           — average HRV in the 24–72 h leading up
//      to a migraine onset vs. all other moments inside the window.
//    • `cyclePhaseSummary`    — per-cycle-day distribution of migraine
//      onsets, gated on the user actually tracking menstrual flow in
//      Apple Health (data-driven, NOT identity-driven).
//
//  The store caches the latest fetch keyed by `(window, migraineCount)`
//  so re-renders during a single dashboard session don't re-hit
//  HealthKit. Filter changes re-load.
//
//  All HealthKit work is gated on `HealthKitManager.shared.isAvailable`
//  + `isAuthorized`, so the store happily produces empty stats on
//  devices without HealthKit (Mac, Simulator without permission, etc).
//
//  Cycle gating is delegated to `HealthKitManager.isCycleInsightsActive`:
//  the HealthKit biological-sex characteristic must not be male, users
//  without a recorded sex must actually log menstrual flow, and the
//  Settings toggle must be on. When any of those fail the cycle card
//  hides entirely and no menstrual samples are fetched.
//

import Foundation
import SwiftUI
import CoreData

/// Snapshot returned by either correlation analysis. The caller decides
/// what "adverse" means (less sleep is bad, less HRV is bad) — we just
/// expose the raw means + sample counts.
struct HealthCorrelationSummary: Equatable {
    /// Mean of the metric on/around migraine days (e.g. hours of sleep
    /// the night before, average HRV in the 72 h pre-migraine window).
    let migraineMean: Double?
    /// Mean of the metric on baseline (non-migraine) days/moments.
    let baselineMean: Double?
    /// How many discrete data points fed `migraineMean`.
    let migraineSampleCount: Int
    /// How many discrete data points fed `baselineMean`.
    let baselineSampleCount: Int
    
    /// Migraine-mean minus baseline-mean. Positive = the metric was
    /// *higher* on migraine days. Sign interpretation depends on the
    /// metric (sleep ↓ is bad; HRV ↓ is bad).
    var delta: Double? {
        guard let m = migraineMean, let b = baselineMean else { return nil }
        return m - b
    }
    
    /// True only when both means are present and we have at least 1
    /// migraine-day sample + 3 baseline samples — below that the
    /// comparison is too noisy to surface.
    var isReliable: Bool {
        guard migraineMean != nil, baselineMean != nil else { return false }
        return migraineSampleCount >= 1 && baselineSampleCount >= 3
    }
}

/// State the store can be in. Drives loading spinners, empty states,
/// and "Connect Health" calls-to-action without leaking authorization
/// strings into the view layer.
///
/// The two "not authorized" cases (`notDetermined` and `denied`) look
/// the same to HealthKit — Apple deliberately collapses them on the
/// read side to prevent fingerprinting — but they trigger
/// **fundamentally different** CTAs:
///
///   • `notDetermined`: we have never called `requestAuthorization`.
///     Surface the in-app primer + system permission sheet.
///   • `denied`: we have called `requestAuthorization`, but reads are
///     not flowing (write-toggle denied, OR no read data despite
///     having asked). Apple does not allow the app to re-prompt;
///     deep-link to iOS Settings instead.
enum HealthCorrelationStatus: Equatable {
    case idle
    case unavailable      // HealthKit not on this device (Mac, etc.)
    case notDetermined    // never asked — show primer + system sheet
    case denied           // asked already — must adjust in iOS Settings
    case loading
    case loaded
    case empty            // authorized but no samples in the window
}

/// Whether cycle analytics can be shown, mirroring
/// `HealthKitManager.isCycleInsightsActive` at the time of the last load.
enum CycleAvailability: Equatable {
    case unknown      // haven't probed yet
    case notTracked   // excluded by sex, no flow history, or toggle off
    case available    // eligible, tracks flow, and toggle on
}

/// Clinical phase a given cycle day falls into. Boundaries follow the
/// most commonly cited 28-day reference; longer cycles still bucket
/// reasonably as long as we extend the luteal phase past day 28 for
/// any leftover days.
enum CyclePhase: String, CaseIterable, Identifiable, Hashable {
    case menses       // days 1-5
    case follicular   // days 6-13
    case ovulatory    // days 14-16
    case luteal       // days 17-28+
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .menses:     return "Menses"
        case .follicular: return "Follicular"
        case .ovulatory:  return "Ovulatory"
        case .luteal:     return "Luteal"
        }
    }
    
    var dayRange: String {
        switch self {
        case .menses:     return "Days 1-5"
        case .follicular: return "Days 6-13"
        case .ovulatory:  return "Days 14-16"
        case .luteal:     return "Days 17+"
        }
    }
    
    static func phase(forCycleDay day: Int) -> CyclePhase {
        switch day {
        case ..<6:    return .menses
        case 6...13:  return .follicular
        case 14...16: return .ovulatory
        default:      return .luteal
        }
    }
}

/// One migraine onset annotated with the cycle day it fell on.
/// `cycleDay` is 1-indexed from the most recent flow start, so day 1
/// is the day the period started; day 5 is four days later, etc.
struct CycleAnchoredMigraine: Identifiable, Hashable {
    var id: Date { onset }
    let onset: Date
    let cycleDay: Int
    var phase: CyclePhase { CyclePhase.phase(forCycleDay: cycleDay) }
    /// `true` when this migraine fell in the perimenstrual window —
    /// the two days before a flow start through the two days after
    /// (see `PerimenstrualWindow`). Because `cycleDay` is anchored to
    /// the *most recent* start, the "two days before" side is only
    /// known when the following start has been logged.
    let perimenstrualOffset: Int?
    var isPerimenstrual: Bool { perimenstrualOffset != nil }
}

/// Aggregated cycle-phase distribution for the migraines that fell on
/// days where we could anchor a cycle (i.e. there was a flow start
/// within the prior 45 days). `unanchoredCount` captures migraines we
/// had to skip — surfaced in the UI so users understand the gap.
struct CyclePhaseDistribution: Equatable {
    let counts: [CyclePhase: Int]
    let perimenstrualCount: Int
    let unanchoredCount: Int
    let totalAnchored: Int
    /// Per-cycle-day count for the histogram in the detail view.
    let perCycleDay: [Int: Int]
    
    var phasePercentage: [CyclePhase: Double] {
        guard totalAnchored > 0 else { return [:] }
        return counts.mapValues { Double($0) / Double(totalAnchored) }
    }
    
    var perimenstrualPercentage: Double? {
        guard totalAnchored > 0 else { return nil }
        return Double(perimenstrualCount) / Double(totalAnchored)
    }
    
    /// True only when there were enough anchored migraines for the
    /// distribution to be meaningful — below that we surface a
    /// "log more cycles" hint instead of confidently named phases.
    var isReliable: Bool { totalAnchored >= 3 }
}

@MainActor
final class HealthCorrelationStore: ObservableObject {
    @Published private(set) var status: HealthCorrelationStatus = .idle
    
    @Published private(set) var sleepSummary: HealthCorrelationSummary?
    @Published private(set) var hrvSummary: HealthCorrelationSummary?
    
    /// Raw historical samples — exposed so detail views can plot the
    /// full series with migraine onset markers.
    @Published private(set) var sleepNights: [SleepNightSample] = []
    @Published private(set) var hrvSamples: [HRVPoint] = []
    
    /// Migraine onsets corresponding to the most recent load — kept on
    /// the store so detail views don't have to re-derive them and so
    /// the chart annotations stay in sync with the loaded sample window.
    @Published private(set) var migraineOnsets: [Date] = []
    
    /// Whether cycle analytics may be shown (see file header). Drives
    /// whether the cycle card surfaces at all on the dashboard.
    @Published private(set) var cycleAvailability: CycleAvailability = .unknown
    
    /// Per-phase distribution of migraine onsets in the current window,
    /// or `nil` when cycle data isn't tracked / no migraines could be
    /// anchored to a recent flow start.
    @Published private(set) var cyclePhaseSummary: CyclePhaseDistribution?
    
    /// Anchored migraines (each tagged with cycle day + phase), kept
    /// on the store so the detail view can plot the histogram without
    /// re-doing the anchoring math.
    @Published private(set) var cycleAnchoredMigraines: [CycleAnchoredMigraine] = []
    
    /// Raw menstrual events for the active window — used by the
    /// detail view to overlay flow-start markers on the timeline.
    @Published private(set) var menstrualEvents: [MenstrualEvent] = []
    
    /// Rate-ratio comparison of migraine days inside vs. outside the
    /// perimenstrual window, or `nil` when no cycle start is known.
    @Published private(set) var cycleAssociation: CycleAssociation?
    
    /// Start-of-day dates of logged flow starts in the window, for the
    /// heatmap overlay. Derived; never persisted.
    @Published private(set) var cycleStartDays: [Date] = []
    
    /// Cache key (window + migraine fingerprint) so we don't re-fetch
    /// when the dashboard re-renders for an unrelated reason.
    private var lastLoadedKey: String?
    private var loadTask: Task<Void, Never>?
    
    /// HRV "pre-migraine" window — how far before each migraine onset
    /// we treat HRV samples as the migraine cohort. 72 h matches the
    /// upper bound of most prodromal-phase research.
    private let hrvLookbackHours: Double = 72
    
    /// Refreshes every cached value for the supplied window. Safe to
    /// call from view modifiers (`onAppear`, `onChange`); duplicate
    /// requests for the same window are de-duplicated.
    func load(window: DateInterval, migraines: [MigraineEvent]) {
        let key = cacheKey(window: window, migraines: migraines)
        if key == lastLoadedKey, status == .loaded || status == .empty { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad(window: window, migraines: migraines, key: key)
        }
    }
    
    private func performLoad(
        window: DateInterval,
        migraines: [MigraineEvent],
        key: String
    ) async {
        let manager = HealthKitManager.shared
        guard manager.isAvailable else {
            status = .unavailable
            cycleAvailability = .notTracked
            resetSamples()
            lastLoadedKey = key
            return
        }

        // `isAuthorized` is an in-memory flag that doesn't survive a
        // cold launch. For a user who previously granted, rehydrate
        // it before deciding we're unauthorized — Apple's
        // `requestAuthorization` no-ops once the user has decided, so
        // this is safe (no UI shown).
        if !manager.isAuthorized && manager.hasRequestedAuthorization {
            await manager.rehydrateAuthorizationStatus()
        }

        guard manager.isAuthorized else {
            // Distinguish "never asked" from "asked-and-denied" using
            // our own UserDefaults flag, since the HealthKit read-side
            // authorization status is intentionally opaque (see
            // `HealthKitManager.hasRequestedAuthorization` doc).
            status = manager.hasRequestedAuthorization ? .denied : .notDetermined
            // Don't downgrade `cycleAvailability` if a previous load
            // already determined the user tracks cycles — that flag is
            // sticky for the lifetime of the store and only flips when
            // we successfully probe the next time.
            resetSamples()
            lastLoadedKey = key
            return
        }
        
        status = .loading
        
        // Sex/history gate + Settings toggle live on the manager; it
        // throttles its own HealthKit reads so this is cheap to repeat.
        await manager.refreshCycleEligibility()
        cycleAvailability = manager.isCycleInsightsActive ? .available : .notTracked
        
        // Capture before kicking off concurrent fetches so the closures
        // don't reach back into the actor-isolated state.
        let shouldFetchMenses = (cycleAvailability == .available)
        
        async let sleepNightsTask = manager.fetchSleepHoursPerNight(in: window)
        async let hrvSamplesTask  = manager.fetchHRVSamples(in: window)
        // Only fetch menstrual events when the user actually tracks them,
        // to keep this dashboard load fast for everyone else.
        async let menstrualTask: [MenstrualEvent] = shouldFetchMenses
            ? manager.fetchMenstrualEvents(in: window)
            : []
        
        let onsets = migraines.compactMap { $0.startTime }.sorted()
        let nights = await sleepNightsTask
        let hrv = await hrvSamplesTask
        let menses = await menstrualTask
        
        guard !Task.isCancelled else { return }
        
        sleepNights = nights
        hrvSamples = hrv
        menstrualEvents = menses
        migraineOnsets = onsets
        sleepSummary = Self.computeSleepCorrelation(nights: nights, migraineOnsets: onsets)
        hrvSummary = Self.computeHRVCorrelation(
            samples: hrv,
            migraineOnsets: onsets,
            lookbackHours: hrvLookbackHours
        )
        let anchored = Self.anchorMigrainesToCycles(onsets: onsets, events: menses)
        cycleAnchoredMigraines = anchored
        cyclePhaseSummary = Self.computeCyclePhaseDistribution(
            anchored: anchored,
            totalMigraines: onsets.count
        )
        let starts = menses.filter(\.isCycleStart).map { Calendar.current.startOfDay(for: $0.date) }
        cycleStartDays = Array(Set(starts)).sorted()
        cycleAssociation = CycleAssociationAnalysis.compute(
            samples: migraines.compactMap { migraine in
                migraine.startTime.map {
                    CycleMigraineSample(onset: $0, painLevel: Int(migraine.painLevel))
                }
            },
            cycleStarts: starts,
            window: window
        )
        
        if nights.isEmpty && hrv.isEmpty && menses.isEmpty {
            status = .empty
        } else {
            status = .loaded
        }
        lastLoadedKey = key
    }
    
    private func resetSamples() {
        sleepSummary = nil
        hrvSummary = nil
        cyclePhaseSummary = nil
        cycleAssociation = nil
        cycleStartDays = []
        sleepNights = []
        hrvSamples = []
        menstrualEvents = []
        cycleAnchoredMigraines = []
        migraineOnsets = []
    }
    
    private func cacheKey(window: DateInterval, migraines: [MigraineEvent]) -> String {
        let start = Int(window.start.timeIntervalSince1970)
        let end   = Int(window.end.timeIntervalSince1970)
        // Use migraine count + most-recent timestamp as a cheap
        // fingerprint — good enough since migraines are append-mostly.
        let count = migraines.count
        let latest = migraines.compactMap { $0.startTime?.timeIntervalSince1970 }.max() ?? 0
        let cycle = HealthKitManager.shared.isCycleInsightsActive ? 1 : 0
        return "\(start)-\(end)-\(count)-\(Int(latest))-\(cycle)"
    }
    
    // MARK: - Pure computations (testable, no HealthKit dependency)
    
    /// Average sleep hours on nights immediately preceding a migraine
    /// vs. all other nights inside the window.
    static func computeSleepCorrelation(
        nights: [SleepNightSample],
        migraineOnsets: [Date]
    ) -> HealthCorrelationSummary? {
        guard !nights.isEmpty else { return nil }
        
        let cal = Calendar.current
        let migraineDays: Set<Date> = Set(migraineOnsets.map { cal.startOfDay(for: $0) })
        
        var migraineHours: [Double] = []
        var baselineHours: [Double] = []
        for night in nights {
            // `night.night` is already startOfDay (the morning the sleep ended).
            if migraineDays.contains(cal.startOfDay(for: night.night)) {
                migraineHours.append(night.hours)
            } else {
                baselineHours.append(night.hours)
            }
        }
        
        return HealthCorrelationSummary(
            migraineMean: migraineHours.mean,
            baselineMean: baselineHours.mean,
            migraineSampleCount: migraineHours.count,
            baselineSampleCount: baselineHours.count
        )
    }
    
    /// Average HRV-SDNN inside the 72 h pre-migraine windows vs. all
    /// other moments inside the window.
    static func computeHRVCorrelation(
        samples: [HRVPoint],
        migraineOnsets: [Date],
        lookbackHours: Double
    ) -> HealthCorrelationSummary? {
        guard !samples.isEmpty else { return nil }
        let lookback = lookbackHours * 3600
        
        // Sorted onsets let us walk the list once and bucket each sample.
        let onsets = migraineOnsets.sorted()
        var migraineValues: [Double] = []
        var baselineValues: [Double] = []
        
        for sample in samples {
            if Self.isInPreMigraineWindow(sample.date, onsets: onsets, lookback: lookback) {
                migraineValues.append(sample.valueMs)
            } else {
                baselineValues.append(sample.valueMs)
            }
        }
        
        return HealthCorrelationSummary(
            migraineMean: migraineValues.mean,
            baselineMean: baselineValues.mean,
            migraineSampleCount: migraineValues.count,
            baselineSampleCount: baselineValues.count
        )
    }
    
    /// True when `date` falls within `lookback` seconds before any
    /// migraine onset. `onsets` must be sorted ascending.
    private static func isInPreMigraineWindow(
        _ date: Date,
        onsets: [Date],
        lookback: TimeInterval
    ) -> Bool {
        // Find the first onset at or after `date` — anything earlier is
        // post-migraine and irrelevant for the prodromal window.
        var lo = 0, hi = onsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if onsets[mid] < date { lo = mid + 1 } else { hi = mid }
        }
        guard lo < onsets.count else { return false }
        let next = onsets[lo]
        return next.timeIntervalSince(date) <= lookback
    }
    
    /// Tags each migraine onset with the cycle day it fell on, defined
    /// as days since the most recent flow start. Migraines that occur
    /// > 45 days after the previous flow start are dropped — at that
    /// distance the data is most likely a tracking gap rather than a
    /// genuine 60-day cycle, and including them would skew the
    /// distribution toward late-luteal noise.
    static func anchorMigrainesToCycles(
        onsets: [Date],
        events: [MenstrualEvent]
    ) -> [CycleAnchoredMigraine] {
        let cycleStarts = events
            .filter(\.isCycleStart)
            .map { Calendar.current.startOfDay(for: $0.date) }
            .sorted()
        guard !cycleStarts.isEmpty else { return [] }
        
        let cal = Calendar.current
        let maxAnchorGap = 45
        var anchored: [CycleAnchoredMigraine] = []
        anchored.reserveCapacity(onsets.count)
        
        for onset in onsets {
            let onsetDay = cal.startOfDay(for: onset)
            // Most-recent cycle start at or before the onset.
            guard let priorStart = cycleStarts.last(where: { $0 <= onsetDay }) else {
                continue
            }
            let dayOffset = cal.dateComponents([.day], from: priorStart, to: onsetDay).day ?? -1
            guard dayOffset >= 0, dayOffset < maxAnchorGap else { continue }
            anchored.append(
                CycleAnchoredMigraine(
                    onset: onset,
                    cycleDay: dayOffset + 1,
                    perimenstrualOffset: PerimenstrualWindow.dayOffset(
                        for: onsetDay,
                        cycleStarts: cycleStarts,
                        calendar: cal
                    )
                )
            )
        }
        return anchored
    }
    
    /// Builds the per-phase / per-day distribution from a list of
    /// already-anchored migraines. `totalMigraines` is the un-anchored
    /// count from the active window so the summary can report how
    /// many we had to skip.
    static func computeCyclePhaseDistribution(
        anchored: [CycleAnchoredMigraine],
        totalMigraines: Int
    ) -> CyclePhaseDistribution? {
        guard !anchored.isEmpty || totalMigraines > 0 else { return nil }
        
        var counts: [CyclePhase: Int] = [:]
        var perDay: [Int: Int] = [:]
        var perimenstrual = 0
        for m in anchored {
            counts[m.phase, default: 0] += 1
            perDay[m.cycleDay, default: 0] += 1
            if m.isPerimenstrual { perimenstrual += 1 }
        }
        let unanchored = max(0, totalMigraines - anchored.count)
        return CyclePhaseDistribution(
            counts: counts,
            perimenstrualCount: perimenstrual,
            unanchoredCount: unanchored,
            totalAnchored: anchored.count,
            perCycleDay: perDay
        )
    }
}

// MARK: - Mean helper

private extension Array where Element == Double {
    /// Returns the arithmetic mean, or `nil` if the array is empty.
    var mean: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
