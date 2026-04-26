//
//  BackgroundTaskScheduler.swift
//  NALI Migraine Log
//
//  Owns our single `BGAppRefreshTask` and the work that runs inside it.
//
//  iOS occasionally wakes apps in the background to refresh content;
//  we use that opportunity to:
//
//    1. Pull the next 24h of weather forecast for the user's last-known
//       location (so the Predict tab has fresh data when they open the
//       app, instead of waiting on a network round-trip).
//    2. Recompute migraine-risk forecasts via `MigrainePredictionService`.
//    3. Hand the result to `NotificationManager.reconcileAllNotifications`
//       so any new high-risk window gets a push and the re-engagement
//       reminder stays accurate.
//
//  The scheduler is wired up in two places:
//
//    • `NALI_Migraine_LogApp.init()` — calls `register()`. This MUST run
//      before `application:didFinishLaunchingWithOptions:` returns or
//      iOS will reject the task identifier with a runtime crash. Doing
//      it from `App.init()` is the SwiftUI-blessed equivalent.
//
//    • `NALI_Migraine_LogApp.scenePhase` (background) — calls
//      `scheduleNextRefresh()`. iOS only honors `submit()` calls made
//      while the app is foregrounded or just-backgrounded, so we kick
//      one off every time we lose focus.
//
//  Identifier policy: a single identifier
//  (`com.neuroli.Headway.refresh`) keeps things simple and keeps us under
//  iOS's 1-task-per-app practical limit. If we add separate tasks later
//  (e.g. a long-running ML retrain) they should be `BGProcessingTask`s
//  with their own identifiers and entitlements.
//
//  iOS-only — `#if os(iOS)`. macOS doesn't use BGTaskScheduler; if we
//  ever want background work there it'll be a `NSBackgroundActivityScheduler`.
//

#if os(iOS)

import Foundation
import BackgroundTasks
import CoreData

@MainActor
enum BackgroundTaskScheduler {

    /// The one identifier we register. Must match an entry in the
    /// `BGTaskSchedulerPermittedIdentifiers` array in Info.plist —
    /// without that match iOS rejects `register` calls with a fatal
    /// "Unknown task identifier" message at app launch.
    static let refreshIdentifier = "com.neuroli.Headway.refresh"

    /// Earliest time we'll ask iOS to wake us. This is a request, not a
    /// guarantee — iOS may wake us much later (or never, on a low-power
    /// device). We use 12 hours so the typical user gets one nightly
    /// run; iOS biases scheduling towards the user's typical app-open
    /// times anyway.
    private static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// Register the task handler. **MUST be called from
    /// `NALI_Migraine_LogApp.init()` before the SwiftUI scene appears**;
    /// calling it later is a UIKit-detected programmer error.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil  // run on a background queue; we'll hop to MainActor inside
        ) { task in
            // BGAppRefreshTask is the narrow type — `task` here is its
            // erased base, so we down-cast on the way in.
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleRefresh(task: refreshTask)
        }
        AppLogger.background.notice("Registered BG task: \(refreshIdentifier, privacy: .public)")
    }

    /// Ask iOS to schedule the next wake. Idempotent; iOS coalesces
    /// duplicate submissions for the same identifier. Failures here are
    /// logged but never thrown — there's nothing the app can do if iOS
    /// refuses the schedule (usually due to background-app-refresh being
    /// disabled in Settings > General).
    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLogger.background.notice("Scheduled next BG refresh in \(refreshInterval / 3600, privacy: .public)h")
        } catch BGTaskScheduler.Error.unavailable {
            AppLogger.background.notice("BG scheduling unavailable (likely Background App Refresh disabled or simulator)")
        } catch {
            AppLogger.background.error("BG schedule failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Handler

    /// Body of the BG task. Runs at most ~30s of CPU before iOS terminates
    /// us, so each step has its own `Task.checkCancellation()`-equivalent
    /// short-circuit and the whole pipeline is structured around the
    /// expirationHandler signaling the task to wind down.
    private static func handleRefresh(task: BGAppRefreshTask) {
        // Schedule the *next* refresh first, before any await — if iOS
        // kills us mid-work we still have a follow-up scheduled.
        scheduleNextRefresh()

        // Hop to MainActor for the actual work since our services are all
        // MainActor-isolated. The `Task` retains itself until the body
        // returns; we cancel via `expirationHandler`.
        let work = Task { @MainActor in
            await performRefreshWork()
        }

        task.expirationHandler = {
            AppLogger.background.notice("BG task expired before completion; cancelling")
            work.cancel()
        }

        // Bridge the structured Task back into the BG task's success/fail
        // signal. iOS uses this to decide whether to grant us future
        // background time — failing too often gets us throttled.
        Task {
            _ = await work.result
            let cancelled = work.isCancelled
            task.setTaskCompleted(success: !cancelled)
            await MainActor.run {
                AppLogger.background.notice("BG task finished (success=\(!cancelled, privacy: .public))")
            }
        }
    }

    /// The actual refresh pipeline. Pulled out into its own function so
    /// it can also be invoked manually from a debug menu or from a
    /// foreground "Refresh now" path later without going through BG
    /// scheduling.
    @MainActor
    private static func performRefreshWork() async {
        AppLogger.background.notice("BG task starting refresh work")

        // 1) Pull the user's last-known weather location & refresh forecast.
        //    No location → no forecast → no risk push. That's fine; the
        //    re-engagement check below still runs.
        var forecastHours: [ForecastHour] = []
        if let location = LocationManager.shared.location {
            let weather = WeatherForecastService.shared
            do {
                forecastHours = try await weather.fetchForecast(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                AppLogger.background.notice("BG forecast refresh ok: \(forecastHours.count, privacy: .public) hours")
            } catch {
                AppLogger.background.error("BG forecast refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 2) Pull all migraines for the prediction + re-engagement decisions.
        //    Done on the view context — same context the UI uses, so any
        //    state we read here is what the user will see when they next
        //    open the app.
        let context = PersistenceController.shared.container.viewContext
        let migraines: [MigraineEvent]
        do {
            let request = MigraineEvent.fetchRequest()
            migraines = try context.fetch(request)
        } catch {
            AppLogger.background.error("BG migraine fetch failed: \(error.localizedDescription, privacy: .public)")
            migraines = []
        }

        // 3) Hand off to the notification manager. It internally gates on
        //    the user's toggle preferences and the OS auth status, so this
        //    is a no-op for users who never opted in.
        await NotificationManager.shared.reconcileAllNotifications(
            migraines: migraines,
            forecast: forecastHours
        )
    }
}

#endif
