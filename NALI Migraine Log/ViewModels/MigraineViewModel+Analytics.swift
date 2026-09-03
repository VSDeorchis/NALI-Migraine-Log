import Foundation

// MARK: - Time-frame filtering and chart cache

extension MigraineViewModel {
    enum TimeFrame: Hashable {
        case week
        case month
        case year
    }

    struct ChartCache {
        var filtered: [TimeFrame: [MigraineEvent]] = [:]
        var triggers: [TimeFrame: [(String, Int)]] = [:]
        var medications: [TimeFrame: [(String, Int)]] = [:]
        var updatedAt: Date?

        func isFresh(within timeout: TimeInterval) -> Bool {
            guard let updatedAt else { return false }
            return Date().timeIntervalSince(updatedAt) < timeout
        }

        mutating func removeAll() {
            filtered.removeAll()
            triggers.removeAll()
            medications.removeAll()
            updatedAt = nil
        }
    }

    func getTriggerFrequency(for timeFilter: TimeFrame) -> [(String, Int)] {
        if chartCache.isFresh(within: chartCacheTimeout),
           let cached = chartCache.triggers[timeFilter] {
            return cached
        }

        var triggerCounts: [String: Int] = [:]
        for migraine in filteredMigraines(for: timeFilter) {
            for trigger in migraine.triggers {
                triggerCounts[trigger.displayName, default: 0] += 1
            }
        }

        let result = triggerCounts.sorted { $0.value > $1.value }
        chartCache.triggers[timeFilter] = result
        chartCache.updatedAt = Date()
        return result
    }

    func getMedicationFrequency(for timeFilter: TimeFrame) -> [(String, Int)] {
        if chartCache.isFresh(within: chartCacheTimeout),
           let cached = chartCache.medications[timeFilter] {
            return cached
        }

        var medicationCounts: [String: Int] = [:]
        for migraine in filteredMigraines(for: timeFilter) {
            for medication in migraine.medications {
                medicationCounts[medication.displayName, default: 0] += 1
            }
        }

        let result = medicationCounts.sorted { $0.value > $1.value }
        chartCache.medications[timeFilter] = result
        chartCache.updatedAt = Date()
        return result
    }

    /// Resets cached chart data when navigation state is reset.
    func clearNavigationSelections() {
        chartCache.removeAll()
    }

    private func filteredMigraines(for timeFrame: TimeFrame) -> [MigraineEvent] {
        if chartCache.isFresh(within: chartCacheTimeout),
           let cached = chartCache.filtered[timeFrame] {
            return cached
        }

        let filtered = migraines.filter { migraine in
            guard let startTime = migraine.startTime else { return false }
            return isDate(startTime, inTimeFrame: timeFrame)
        }

        chartCache.filtered[timeFrame] = filtered
        chartCache.updatedAt = Date()
        return filtered
    }

    func invalidateCache() {
        chartCache.removeAll()
        objectWillChange.send()
    }

    private func isDate(_ date: Date, inTimeFrame timeFrame: TimeFrame) -> Bool {
        guard let interval = Self.interval(for: timeFrame, containing: Date()) else {
            return false
        }
        return interval.contains(date) && date < interval.end
    }

    /// Calendar interval (week / month / year) containing `reference`, or
    /// `nil` if the calendar cannot produce one for that instant.
    private static func interval(for timeFrame: TimeFrame, containing reference: Date) -> DateInterval? {
        let component: Calendar.Component
        switch timeFrame {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return Calendar.current.dateInterval(of: component, for: reference)
    }

    /// Warms the chart caches for `timeFilter`. Every helper it calls only
    /// touches in-memory state, so the work is done inline on the main
    /// actor rather than hopping to a detached task and back.
    @MainActor
    func loadChartData(for timeFilter: TimeFrame) async {
        guard !chartCache.isFresh(within: chartCacheTimeout) else { return }

        chartCache.filtered[timeFilter] = filteredMigraines(for: timeFilter)
        chartCache.triggers[timeFilter] = getTriggerFrequency(for: timeFilter)
        chartCache.medications[timeFilter] = getMedicationFrequency(for: timeFilter)
        chartCache.updatedAt = Date()
        objectWillChange.send()
    }
}
