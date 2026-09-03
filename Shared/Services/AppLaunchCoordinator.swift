//
//  AppLaunchCoordinator.swift
//  NALI Migraine Log
//
//  Runs the one-time launch work (legacy data import, version upgrade
//  steps) from a `.task` on the root view instead of `App.init()`, so the
//  UI can show progress and the splash dismisses as soon as the work is
//  done rather than after a fixed delay.
//

import CoreData
import Foundation
import Observation

struct LaunchStep: Sendable {
    let title: String
    let perform: @MainActor @Sendable (NSManagedObjectContext) throws -> Void
}

@MainActor
@Observable
final class AppLaunchCoordinator {
    enum Phase: Equatable {
        case pending
        case running(step: String, index: Int)
        case ready
        case failed(step: String, message: String)
    }

    private(set) var phase: Phase = .pending
    let steps: [LaunchStep]
    /// Keeps the branded splash on screen long enough to avoid a one-frame
    /// flash when launch work finishes immediately (the common case).
    let minimumSplashDuration: Duration

    var isReady: Bool { phase == .ready }

    var progress: Double {
        switch phase {
        case .pending: return 0
        case .running(_, let index): return steps.isEmpty ? 1 : Double(index) / Double(steps.count)
        case .ready, .failed: return 1
        }
    }

    init(steps: [LaunchStep], minimumSplashDuration: Duration = .milliseconds(750)) {
        self.steps = steps
        self.minimumSplashDuration = minimumSplashDuration
    }

    /// Idempotent: a second call while ready is a no-op, a call after a
    /// failure retries from the failed step.
    func run(context: NSManagedObjectContext) async {
        guard phase != .ready else { return }
        await run(context: context, from: failedIndex ?? 0)
    }

    /// Lets the user proceed past a failed non-critical step; the step's
    /// own bookkeeping decides whether it retries on the next launch.
    func skipFailedStep(context: NSManagedObjectContext) async {
        guard let index = failedIndex else { return }
        await run(context: context, from: index + 1)
    }

    private var failedIndex: Int? {
        guard case .failed(let step, _) = phase else { return nil }
        return steps.firstIndex { $0.title == step }
    }

    private func run(context: NSManagedObjectContext, from startIndex: Int) async {
        let start = ContinuousClock.now

        for (index, step) in steps.enumerated() where index >= startIndex {
            phase = .running(step: step.title, index: index)
            await Task.yield()
            do {
                try step.perform(context)
            } catch {
                AppLogger.migration.error("Launch step \(step.title, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
                phase = .failed(step: step.title, message: error.localizedDescription)
                return
            }
        }

        let elapsed = ContinuousClock.now - start
        if elapsed < minimumSplashDuration {
            try? await Task.sleep(for: minimumSplashDuration - elapsed)
        }
        phase = .ready
    }
}
