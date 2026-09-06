import CoreData
import Foundation

// MARK: - CloudKit status and auto-sync

extension MigraineViewModel {
    func setupAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil

        // Only setup timer if sync is enabled
        guard case .enabled = syncStatus else { return }

        let interval = autoSyncInterval
        autoSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                self.checkAndSync()
            }
        }
    }

    private func checkAndSync() {
        guard case .pendingChanges = syncStatus else { return }
        syncPendingChanges()
    }

    func handleSyncStatusChange(_ status: SyncStatus) {
        syncStatus = status
        switch status {
        case .enabled:
            setupAutoSync()
        case .disabled:
            autoSyncTask?.cancel()
            autoSyncTask = nil
            AppLogger.sync.notice("CloudKit sync disabled — using local storage only")
        case .error, .signInRequired:
            autoSyncTask?.cancel()
            autoSyncTask = nil
        case .notConfigured, .pendingChanges, .syncing:
            break
        }
    }

    @objc func handleAppBackground() {
        // Sync immediately when app goes to background
        checkAndSync()
    }

    @objc func handleAppForeground() {
        // Check for changes and setup sync timer when app comes to foreground
        setupAutoSync()
        checkAndSync()
    }

    func syncPendingChanges() {
        guard case .pendingChanges = syncStatus else { return }

        syncStatus = .syncing(0.0)

        do {
            try viewContext.save()

            // Mark sync as complete after a short delay
            // (Avoids rapid @Published updates that cause excessive re-renders)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.syncStatus = .enabled
                self?.lastSyncTime = Date()
                self?.pendingChanges = 0
            }
        } catch {
            syncStatus = .error("Sync failed: \(error.localizedDescription)")
            // Retry after delay
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.checkAndSync()
            }
        }
    }

    func migrateToDifferentStore() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PersistenceController.shared.migrateDataToNewStore { (result: Result<Void, Error>) in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
