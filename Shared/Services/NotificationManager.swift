//
//  NotificationManager.swift
//  NALI Migraine Log
//
//  Single owner of every UNUserNotification we ever schedule. Two
//  notification kinds are supported today:
//
//  1. **Forecast-risk** — fires *only when* the next 24 hours of weather
//     forecast contains an hour the prediction engine scores ≥ 0.65 risk
//     AND the user has logged enough history for the engine to be
//     calibrated (≥ 5 migraines). Body is informational, never asks
//     "how are you feeling?" per product direction. Schedule key is the
//     trigger hour, so re-running the scheduler is idempotent.
//
//  2. **Re-engagement** — fires daily at 7pm local time *only after*
//     `reengagementDays` (default 14) have elapsed since the user's most
//     recent migraine entry. Phrased as a gentle "anything to log?" —
//     never as a wellness check, never asks how the user feels. Cancelled
//     automatically on every app foreground (hence the "...IfNeeded"
//     names everywhere — every method in here is safe to call on every
//     app cycle).
//
//  Permission model:
//    • Authorization is requested *lazily*, the first time the user
//      enables either toggle in Settings. We never ask on cold launch
//      because users who don't care about either feature shouldn't see
//      the prompt at all.
//    • If the user later denies in System Settings, every schedule call
//      will silently no-op (UN system enforces this). We update
//      `isAuthorized` from `getNotificationSettings` on every refresh.
//
//  Platform: iOS-only for now (`#if os(iOS)`). The macOS app surfaces the
//  same data through its menu bar widgets, and watchOS gets notifications
//  for free via the iPhone pairing.
//

#if os(iOS)

import Foundation
import UserNotifications
import CoreData

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    // MARK: - UserDefaults keys

    private static let forecastEnabledKey   = "notifications.forecastRiskEnabled"
    private static let reengagementEnabledKey = "notifications.reengagementEnabled"
    private static let reengagementDaysKey  = "notifications.reengagementDays"

    /// Default re-engagement window. 14 days is long enough that occasional
    /// migraine sufferers don't get nagged after a quiet stretch, short
    /// enough that someone falling out of the habit gets a nudge before
    /// the data gap becomes self-reinforcing.
    private static let defaultReengagementDays = 14

    /// Risk threshold (0.0–1.0) at or above which we'll schedule a
    /// forecast-risk push. Matches `MigraineRiskScore.tier` boundaries —
    /// 0.65 corresponds to the "high" band in the in-app UI, so the
    /// notification only fires when the user would also see a red dot
    /// on the Predict tab.
    private static let highRiskThreshold = 0.65

    /// Minimum migraine history before forecast risk pushes are allowed.
    /// Sending "your forecast looks risky" notifications to a user with
    /// only 2 logged entries would be using their data to predict a
    /// pattern that doesn't yet exist — we wait until the prediction
    /// engine has enough signal to be worth listening to.
    private static let minimumHistoryForForecast = 5

    // MARK: - Identifiers

    private static let forecastIdentifierPrefix = "headway.forecast."
    private static let reengagementIdentifier   = "headway.reengagement"

    // MARK: - Published state

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// True iff the user has granted (or provisionally granted)
    /// notification permission. Updated by `refreshAuthorizationStatus()`.
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    @Published var forecastRiskEnabled: Bool {
        didSet {
            UserDefaults.standard.set(forecastRiskEnabled, forKey: Self.forecastEnabledKey)
            AppLogger.notifications.notice("Forecast risk notifications \(self.forecastRiskEnabled ? "enabled" : "disabled", privacy: .public)")
            if !forecastRiskEnabled {
                Task { await self.cancelAllForecastRiskNotifications() }
            }
        }
    }

    @Published var reengagementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(reengagementEnabled, forKey: Self.reengagementEnabledKey)
            AppLogger.notifications.notice("Re-engagement notifications \(self.reengagementEnabled ? "enabled" : "disabled", privacy: .public)")
            if !reengagementEnabled {
                Task { await self.cancelReengagementNotifications() }
            }
        }
    }

    /// Number of days of inactivity before re-engagement notifications
    /// start firing. Stored in UserDefaults so the user could conceivably
    /// override it from a debug menu later; the Settings UI exposes it
    /// indirectly via the toggle copy.
    var reengagementDays: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.reengagementDaysKey)
            return stored > 0 ? stored : Self.defaultReengagementDays
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.reengagementDaysKey)
        }
    }

    private let center = UNUserNotificationCenter.current()

    private init() {
        // Both toggles default to `false`. They can only become `true` after
        // the user explicitly enables them in Settings, which also triggers
        // an authorization request.
        self.forecastRiskEnabled = UserDefaults.standard.bool(forKey: Self.forecastEnabledKey)
        self.reengagementEnabled = UserDefaults.standard.bool(forKey: Self.reengagementEnabledKey)

        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Authorization

    /// Pull the current system-level auth status into our published
    /// `authorizationStatus`. Cheap and idempotent — call on every app
    /// foreground so a Settings.app revoke is reflected immediately.
    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }

    /// Prompt for notification permission. Returns `true` on grant. Safe to
    /// call repeatedly — after the first call the system returns the
    /// existing decision without re-prompting.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            AppLogger.notifications.notice("Notification authorization \(granted ? "granted" : "denied", privacy: .public)")
            return granted
        } catch {
            AppLogger.notifications.error("Notification authorization error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Forecast-risk notifications

    /// Inspect `forecast` against `migraines` and schedule a single
    /// forecast-risk notification when an upcoming hour scores ≥
    /// `highRiskThreshold`. Idempotent on re-runs — the identifier is
    /// derived from the trigger hour, so repeat calls won't stack.
    ///
    /// Called by the BG task handler nightly and by the app on foreground.
    /// We do not call this on every Core Data change because forecast
    /// fetches are themselves rate-limited at the WeatherKit layer.
    func scheduleForecastRiskNotificationIfNeeded(
        migraines: [MigraineEvent],
        forecast: [ForecastHour]
    ) async {
        guard forecastRiskEnabled, isAuthorized else { return }
        guard migraines.count >= Self.minimumHistoryForForecast else {
            AppLogger.notifications.debug("Forecast push skipped: only \(migraines.count, privacy: .public) entries logged (need \(Self.minimumHistoryForForecast, privacy: .public))")
            return
        }
        guard !forecast.isEmpty else { return }

        // Use the same engine the in-app UI uses, so the user can
        // cross-reference the push against the Predict tab without seeing
        // contradictory numbers.
        let predictor = MigrainePredictionService.shared
        let hourlyForecast = predictor.generate24HourForecast(
            migraines: migraines,
            forecastHours: forecast
        )

        // Find the *first* hour in the next 24h that crosses the threshold.
        // Multiple high-risk windows back-to-back collapse to one push —
        // we deliberately don't fire on every spike because users would
        // turn the feature off after the second consecutive ping.
        guard let peak = hourlyForecast
            .first(where: { $0.risk >= Self.highRiskThreshold }),
              let peakDate = peak.date
        else {
            AppLogger.notifications.debug("Forecast push skipped: no hour above threshold")
            return
        }

        // Schedule the alert ~2 hours before the predicted hour to give
        // the user time to take preventive action (hydrate, take prophy
        // meds, dim screens, cancel a stressful afternoon). When the
        // peak is closer than 2 hours away, fire immediately — late
        // warnings are still better than no warning.
        let triggerDate = max(
            Date().addingTimeInterval(60),
            peakDate.addingTimeInterval(-2 * 3600)
        )
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = "Possible migraine pattern ahead"
        // Body deliberately states observation + opportunity, never asks
        // for self-report. Per product direction we do NOT say "how are
        // you feeling?" anywhere.
        content.body = "Weather conditions in the next few hours match patterns from your past migraines. Hydrate, eat something, and avoid skipping meds if you take them."
        content.sound = .default
        content.threadIdentifier = "headway.forecast"

        let id = forecastIdentifier(for: peakDate)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            // Cancel any prior forecast pushes — we only want one in flight
            // at a time, and the identifier scheme means stale ones from
            // earlier scheduling cycles won't get auto-replaced.
            await cancelAllForecastRiskNotifications()
            try await center.add(request)
            AppLogger.notifications.notice("Scheduled forecast push id=\(id, privacy: .public) for \(triggerDate.description, privacy: .public) (peak risk=\(peak.risk, privacy: .public))")
        } catch {
            AppLogger.notifications.error("Failed to schedule forecast push: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stable identifier for a forecast trigger hour. Same input → same id,
    /// so a second call from the same scheduling cycle replaces rather
    /// than duplicates the push.
    private func forecastIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HH"
        formatter.timeZone = TimeZone.current
        return Self.forecastIdentifierPrefix + formatter.string(from: date)
    }

    /// Wipe every pending forecast-risk push. Called from the toggle's
    /// `didSet`, the start of every reschedule cycle, and the BG task's
    /// expiration handler. Pulls the full pending list from the center
    /// rather than tracking ids ourselves so we can't leak.
    func cancelAllForecastRiskNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.forecastIdentifierPrefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            AppLogger.notifications.notice("Cancelled \(ids.count, privacy: .public) pending forecast pushes")
        }
    }

    // MARK: - Re-engagement notifications

    /// Schedule (or re-schedule) the daily 7pm re-engagement reminder if
    /// the user has been quiet for `reengagementDays` or longer. Cancels
    /// the prior reminder on every call so we always converge on a single
    /// pending request.
    ///
    /// Per product direction the body is phrased around "anything to
    /// catch up on?" — never around feelings or current status.
    func scheduleReengagementNotificationIfNeeded(migraines: [MigraineEvent]) async {
        guard reengagementEnabled, isAuthorized else { return }

        let lastActivity = lastUserActivityDate(migraines: migraines)
        let daysSince = Calendar.current.dateComponents([.day], from: lastActivity, to: Date()).day ?? 0

        if daysSince < reengagementDays {
            // Still inside the quiet window; clear any stale schedule and
            // bail. We'll re-evaluate on the next BG run / app open.
            await cancelReengagementNotifications()
            AppLogger.notifications.debug("Re-engagement skipped: only \(daysSince, privacy: .public) days since last activity")
            return
        }

        // Daily 7pm local. `repeats: true` means we don't have to keep
        // re-scheduling; it'll keep firing until the user opens the app
        // (which calls `cancelReengagementNotifications()` and then this
        // method again, at which point `daysSince` will be 0 and we'll
        // bail at the guard above).
        var components = DateComponents()
        components.hour = 19
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Anything to add to Headway?"
        content.body = "It's been a while since your last entry. If you've had any migraines, take a moment to log them so your trends stay accurate."
        content.sound = .default
        content.threadIdentifier = "headway.reengagement"

        let request = UNNotificationRequest(
            identifier: Self.reengagementIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            await cancelReengagementNotifications()
            try await center.add(request)
            AppLogger.notifications.notice("Scheduled re-engagement push (last activity \(daysSince, privacy: .public) days ago)")
        } catch {
            AppLogger.notifications.error("Failed to schedule re-engagement push: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wipe the pending re-engagement reminder. Called by the toggle's
    /// `didSet`, on every successful migraine save (handled at the call
    /// site in `MigraineViewModel`), and on app foreground.
    func cancelReengagementNotifications() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reengagementIdentifier])
    }

    /// "Last activity" anchors re-engagement to the most recent of:
    ///   • the user's last logged migraine `startTime`
    ///   • the install date (so a brand-new user with zero entries doesn't
    ///     get pinged on day 14 — there's nothing for them to catch up on)
    private func lastUserActivityDate(migraines: [MigraineEvent]) -> Date {
        let lastMigraine = migraines
            .compactMap(\.startTime)
            .max() ?? .distantPast

        // Install date proxy: ReviewPromptCoordinator writes `firstLaunchDate`
        // on the first launch. If for some reason it's missing (legacy
        // upgrade from before the coordinator existed), fall back to "now"
        // so we don't immediately fire a re-engagement push.
        let firstLaunch = ReviewPromptCoordinator.firstLaunchDate ?? Date()

        return max(lastMigraine, firstLaunch)
    }

    // MARK: - Convenience entry point

    /// One-shot "make notifications correct for the current Core Data
    /// state". Called by the BG task handler and by the app's foreground
    /// hook. Internally cheap: each sub-call early-returns when its
    /// preconditions aren't met.
    func reconcileAllNotifications(
        migraines: [MigraineEvent],
        forecast: [ForecastHour]
    ) async {
        await refreshAuthorizationStatus()
        await scheduleForecastRiskNotificationIfNeeded(migraines: migraines, forecast: forecast)
        await scheduleReengagementNotificationIfNeeded(migraines: migraines)
    }
}

#endif
