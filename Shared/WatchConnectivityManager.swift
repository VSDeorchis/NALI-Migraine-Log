#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity
import CoreData
import SwiftUI

/// Bridge between the iOS and watchOS apps via `WCSession`.
///
/// **Sync protocol (v2):**
/// - Each device sends a *delta* (`WatchSyncEnvelope.Kind.delta`) containing
///   only the entries it created/edited itself, via `transferUserInfo`. The OS
///   queues transfers until the counterpart is available, so a Watch-logged
///   migraine reaches the phone even if it was logged offline. Dirty ids are
///   persisted until the transfer is acknowledged in
///   `session(_:didFinish:error:)`.
/// - The phone additionally publishes a compact *snapshot* of recent history
///   (no notes / coordinates / weather) through `updateApplicationContext` so
///   a freshly installed Watch app has data to show. Snapshot records never
///   overwrite entries the receiver has locally edited but not yet delivered.
/// - Deletions travel as tombstones (`deletedIDs`) in both message kinds and
///   are pruned after `tombstoneRetention`.
///
/// **Concurrency model (Swift 6-clean):**
/// The class is `@MainActor` so every read/write of `@Published` state and
/// every Core Data operation against `viewContext` runs on the main thread.
/// All Apple framework callbacks (`WCSessionDelegate`, `WCSession.sendMessage`
/// errorHandlers) are `nonisolated` and hop to MainActor before touching
/// `self`.
@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    private let session: WCSession
    private let context: NSManagedObjectContext

    @Published var isPaired = false
    @Published var isReachable = false
    @Published var lastSyncTime: Date?

    /// Risk summary most recently received from the iPhone (used by watchOS).
    @Published var syncedRisk: WatchRiskPayload?

    /// Entries this device changed and has not yet delivered to the counterpart.
    private var pendingChangeIDs: Set<UUID> = []
    /// Dirty ids grouped by in-flight `transferUserInfo` batch.
    private var inFlightBatches: [UUID: Set<UUID>] = [:]
    /// Deleted entry id → time of deletion.
    private var tombstones: [UUID: Date] = [:]
    private var snapshotTask: Task<Void, Never>?

    private let tombstonesKey = "com.neuroli.migraineTombstones"
    /// Pre-`modifiedAt` bookkeeping; cleared on first launch of this build.
    private let legacyRevisionsKey = "com.neuroli.migraineSyncRevisions"
    private let pendingChangesKey = "com.neuroli.pendingWatchSyncIds"
    private let legacyDeletedIdsKey = "com.neuroli.deletedMigraineIds"
    private let pendingRiskKey = "pendingRiskPayload"

    private let tombstoneRetention: TimeInterval = 90 * 86_400
    /// Upper bound on entries included in a phone → Watch snapshot.
    private let snapshotLimit = 150
    /// Conservative ceiling for a single application-context payload.
    private let snapshotByteBudget = 60_000

    init(session: WCSession = .default) {
        self.session = session
        self.context = PersistenceController.shared.container.viewContext
        super.init()

        loadPersistedState()

        if WCSession.isSupported() {
            AppLogger.watch.debug("WCSession is supported")
            session.delegate = self
            session.activate()
        }

        #if os(iOS)
        // Entries that arrive from CloudKit (edited on a Mac, another phone)
        // never pass through the view model, so refresh the Watch snapshot
        // when the store reports remote changes.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSnapshot()
            }
        }
        #endif
    }

    // MARK: - Persistence of sync bookkeeping

    private func loadPersistedState() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: tombstonesKey),
           let stored = try? JSONDecoder().decode([UUID: Date].self, from: data) {
            tombstones = stored
        }
        // One-time migration from the pre-v2 `Set<UUID>` format.
        if let legacy = defaults.data(forKey: legacyDeletedIdsKey),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: legacy) {
            let now = Date()
            for id in ids where tombstones[id] == nil {
                tombstones[id] = now
            }
            defaults.removeObject(forKey: legacyDeletedIdsKey)
            saveTombstones()
        }
        if let data = defaults.data(forKey: pendingChangesKey),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            pendingChangeIDs = ids
        }
        defaults.removeObject(forKey: legacyRevisionsKey)
        pruneTombstones()
    }

    private func saveTombstones() {
        if let data = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(data, forKey: tombstonesKey)
        }
    }

    private func savePendingChanges() {
        if let data = try? JSONEncoder().encode(pendingChangeIDs) {
            UserDefaults.standard.set(data, forKey: pendingChangesKey)
        }
    }

    private func pruneTombstones() {
        let cutoff = Date().addingTimeInterval(-tombstoneRetention)
        let before = tombstones.count
        tombstones = tombstones.filter { $0.value >= cutoff }
        if tombstones.count != before {
            saveTombstones()
        }
    }

    /// Forget all bookkeeping. Used when the user erases all app data.
    func resetSyncState() {
        pendingChangeIDs.removeAll()
        inFlightBatches.removeAll()
        tombstones.removeAll()
        savePendingChanges()
        saveTombstones()
        UserDefaults.standard.removeObject(forKey: pendingRiskKey)
    }

    // MARK: - Public change notifications (called by the view models)

    /// Marks an entry as changed on this device and queues a delta transfer.
    func recordChange(of migraineId: UUID) {
        pendingChangeIDs.insert(migraineId)
        savePendingChanges()
        flushPendingChanges()
        scheduleSnapshot()
    }

    /// Records a deletion tombstone and queues a delta transfer.
    func recordDeletion(of migraineId: UUID) {
        recordDeletions(of: [migraineId])
    }

    /// Records tombstones for many entries at once (e.g. "delete all").
    func recordDeletions(of migraineIds: [UUID]) {
        let now = Date()
        for id in migraineIds {
            tombstones[id] = now
            pendingChangeIDs.remove(id)
        }
        saveTombstones()
        savePendingChanges()
        flushPendingChanges(forceTombstones: true)
        scheduleSnapshot()
    }

    // MARK: - Outbound: deltas

    /// Sends every un-acknowledged local change (and current tombstones) as a
    /// single queued `transferUserInfo`. Safe to call repeatedly; ids already
    /// in flight are skipped.
    private func flushPendingChanges(forceTombstones: Bool = false) {
        guard session.activationState == .activated else {
            AppLogger.watch.debug("Session not activated; delta deferred")
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else {
            AppLogger.watch.debug("No Watch app installed; delta skipped")
            return
        }
        #endif

        let inFlight = inFlightBatches.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        let idsToSend = pendingChangeIDs.subtracting(inFlight)
        guard !idsToSend.isEmpty || (forceTombstones && !tombstones.isEmpty) else { return }

        var records: [MigraineSyncRecord] = []
        if !idsToSend.isEmpty {
            let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
            request.predicate = NSPredicate(format: "id IN %@", Array(idsToSend))
            do {
                let events = try context.fetch(request)
                records = events.compactMap { MigraineSyncRecord(event: $0, includeNotes: true) }
            } catch {
                AppLogger.watch.error("Failed to fetch pending entries: \(error.localizedDescription, privacy: .private)")
                return
            }
            // Ids that no longer resolve to an object were deleted locally;
            // drop them from the dirty set so they don't retry forever.
            let found = Set(records.map(\.id))
            for missing in idsToSend.subtracting(found) {
                pendingChangeIDs.remove(missing)
            }
            savePendingChanges()
        }

        let envelope = WatchSyncEnvelope(
            kind: .delta,
            sentAt: Date(),
            records: records,
            deletedIDs: Array(tombstones.keys)
        )

        do {
            let batchID = UUID()
            let payload: [String: Any] = [
                WatchSyncEnvelope.payloadKey: try envelope.encoded(),
                WatchSyncEnvelope.batchIDKey: batchID.uuidString
            ]
            inFlightBatches[batchID] = Set(records.map(\.id))
            session.transferUserInfo(payload)
            AppLogger.watch.info("Queued delta: \(records.count, privacy: .public) entries, \(envelope.deletedIDs.count, privacy: .public) tombstones")
        } catch {
            AppLogger.watch.error("Failed to encode delta: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func completeBatch(_ batchID: UUID, error: Error?) {
        guard let ids = inFlightBatches.removeValue(forKey: batchID) else { return }
        if let error {
            AppLogger.watch.error("Delta transfer failed; will retry: \(error.localizedDescription, privacy: .private)")
            // Ids stay in `pendingChangeIDs`; next flush retries them.
            return
        }
        pendingChangeIDs.subtract(ids)
        savePendingChanges()
        lastSyncTime = Date()
        AppLogger.watch.info("Delta acknowledged: \(ids.count, privacy: .public) entries")
    }

    // MARK: - Outbound: snapshot (iOS → watchOS)

    /// Debounces snapshot publication so a burst of edits produces one
    /// application-context update.
    private func scheduleSnapshot() {
        #if os(iOS)
        snapshotTask?.cancel()
        snapshotTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.sendSnapshot()
        }
        #endif
    }

    /// Publishes recent history to the Watch. No-op on watchOS.
    func sendSnapshot() {
        #if os(iOS)
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else {
            return
        }

        let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MigraineEvent.startTime, ascending: false)]
        request.fetchLimit = snapshotLimit

        let records: [MigraineSyncRecord]
        do {
            records = try context.fetch(request).compactMap { MigraineSyncRecord(event: $0, includeNotes: false) }
        } catch {
            AppLogger.watch.error("Snapshot fetch failed: \(error.localizedDescription, privacy: .private)")
            return
        }

        var limit = records.count
        var applicationContext: [String: Any] = [:]
        // Shrink until the payload fits the budget.
        repeat {
            let envelope = WatchSyncEnvelope(
                kind: .snapshot,
                sentAt: Date(),
                records: Array(records.prefix(limit)),
                deletedIDs: Array(tombstones.keys)
            )
            guard let data = try? envelope.encoded() else {
                AppLogger.watch.error("Snapshot encoding failed")
                return
            }
            if data.count <= snapshotByteBudget || limit == 0 {
                applicationContext[WatchSyncEnvelope.payloadKey] = data
                break
            }
            limit /= 2
        } while true

        if let pendingRisk = UserDefaults.standard.data(forKey: pendingRiskKey) {
            applicationContext[WatchRiskPayload.payloadKey] = pendingRisk
        }

        do {
            try session.updateApplicationContext(applicationContext)
            lastSyncTime = Date()
            AppLogger.watch.info("Published snapshot with \(limit, privacy: .public) entries")
        } catch {
            AppLogger.watch.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .private)")
        }
        #endif
    }

    // MARK: - Risk score (iOS → watchOS)

    #if os(iOS)
    /// Send the computed risk score to the Watch so both platforms show the same value.
    func sendRiskScore(_ riskScore: MigraineRiskScore) {
        guard session.activationState == .activated else { return }

        let payload = WatchRiskPayload(riskScore: riskScore)
        guard let data = try? payload.encoded() else {
            AppLogger.watch.error("Failed to encode risk payload")
            return
        }

        if session.isReachable {
            session.sendMessage([WatchRiskPayload.payloadKey: data], replyHandler: nil) { error in
                AppLogger.watch.error("Error sending risk to Watch: \(error.localizedDescription, privacy: .private)")
            }
        }

        // Also include in the next application context update so the Watch gets it eventually.
        UserDefaults.standard.set(data, forKey: pendingRiskKey)
        scheduleSnapshot()
    }
    #endif

    #if os(watchOS)
    /// Ask the paired iPhone to publish a fresh snapshot.
    func requestFullSync() {
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["requestSync": true], replyHandler: nil) { error in
            AppLogger.watch.error("Error requesting sync: \(error.localizedDescription, privacy: .private)")
        }
    }

    #endif

    // MARK: - Inbound

    private func handleIncoming(_ payload: [String: Any]) {
        if let envelope = WatchSyncEnvelope.decode(from: payload) {
            apply(envelope)
        } else if let legacyRecords = payload["migraineData"] as? [[String: Any]],
                  let legacyDeleted = payload["deletedIds"] as? [String] {
            applyLegacy(records: legacyRecords, deletedIds: legacyDeleted)
        }
        #if os(watchOS)
        if let risk = WatchRiskPayload.decode(from: payload) {
            if let current = syncedRisk, current.timestamp > risk.timestamp {
                return
            }
            syncedRisk = risk
        }
        #endif
    }

    private func apply(_ envelope: WatchSyncEnvelope) {
        var applied = 0
        var skipped = 0

        applyTombstones(envelope.deletedIDs)

        let incomingIDs = envelope.records.map(\.id)
        var existing: [UUID: MigraineEvent] = [:]
        if !incomingIDs.isEmpty {
            let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
            request.predicate = NSPredicate(format: "id IN %@", incomingIDs)
            do {
                for event in try context.fetch(request) {
                    if let id = event.id { existing[id] = event }
                }
            } catch {
                AppLogger.watch.error("Inbound lookup failed: \(error.localizedDescription, privacy: .private)")
                return
            }
        }

        for record in envelope.records {
            let resolution = WatchSyncEnvelope.resolve(
                incoming: record,
                kind: envelope.kind,
                localRevision: existing[record.id]?.revision,
                isTombstoned: tombstones[record.id] != nil,
                hasPendingLocalEdit: pendingChangeIDs.contains(record.id)
            )
            guard resolution == .apply else {
                skipped += 1
                continue
            }
            let event: MigraineEvent
            if let match = existing[record.id] {
                event = match
            } else {
                event = MigraineEvent(context: context)
                existing[record.id] = event
            }
            record.apply(to: event)
            applied += 1
        }

        saveIfNeeded(applied: applied, skipped: skipped, kind: envelope.kind.rawValue)
    }

    /// Accepts payloads from pre-v2 app versions. Insert-only: it never
    /// overwrites an existing local entry, so a stale counterpart cannot roll
    /// back edits made here.
    private func applyLegacy(records: [[String: Any]], deletedIds: [String]) {
        applyTombstones(deletedIds.compactMap(UUID.init(uuidString:)))

        var applied = 0
        for dict in records {
            guard let idString = dict["id"] as? String,
                  let id = UUID(uuidString: idString),
                  tombstones[id] == nil else { continue }

            let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let count = try? context.count(for: request), count == 0 else { continue }

            let event = MigraineEvent(context: context)
            event.id = id
            event.updateFromDictionary(dict)
            if !MigraineSyncRecord.painLevelRange.contains(Int(event.painLevel)) {
                context.delete(event)
                continue
            }
            applied += 1
        }
        saveIfNeeded(applied: applied, skipped: 0, kind: "legacy")
    }

    private func applyTombstones(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let now = Date()
        for id in ids where tombstones[id] == nil {
            tombstones[id] = now
            pendingChangeIDs.remove(id)
        }
        saveTombstones()
        savePendingChanges()

        let request = NSFetchRequest<MigraineEvent>(entityName: "MigraineEvent")
        request.predicate = NSPredicate(format: "id IN %@", ids)
        do {
            for event in try context.fetch(request) {
                context.delete(event)
            }
        } catch {
            AppLogger.watch.error("Error applying tombstones: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func saveIfNeeded(applied: Int, skipped: Int, kind: String) {
        guard context.hasChanges else { return }
        do {
            try context.save()
            AppLogger.watch.info("Applied \(kind, privacy: .public): \(applied, privacy: .public) upserts, \(skipped, privacy: .public) skipped")
        } catch {
            AppLogger.watch.error("Error saving inbound sync: \(error.localizedDescription, privacy: .private)")
            context.rollback()
        }
    }

    /// Handles a counterpart's request for fresh data. On iOS this also
    /// recomputes and pushes the current risk score, so a Watch that has
    /// just launched gets the phone's weather/Health-aware number without
    /// the user opening the Predict tab.
    func handleSyncRequest() {
        flushPendingChanges(forceTombstones: true)
        sendSnapshot()
        #if os(iOS)
        Task { await RiskSyncCoordinator.refreshFromStore() }
        #endif
    }
}

// MARK: - WCSessionDelegate
//
// Every method here is called by the WatchConnectivity framework on a
// background queue. Marking the methods `nonisolated` makes the conformance
// legal under Swift 6 strict-concurrency, and we explicitly hop to
// `@MainActor` inside each method before touching any `self` state. Values
// captured into the `Task` (session flags, payload dictionaries, primitives)
// are all Sendable.
extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let isPaired: Bool
        let isReachable: Bool
        #if os(iOS)
        isPaired = session.isPaired
        isReachable = session.isReachable
        #else
        isPaired = false
        isReachable = session.isReachable
        #endif
        let activationError = error

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let activationError {
                AppLogger.watch.error("Session activation failed: \(activationError.localizedDescription, privacy: .private)")
                return
            }
            AppLogger.watch.info("Session activated successfully")
            self.isPaired = isPaired
            self.isReachable = isReachable
            #if os(iOS)
            self.handleSyncRequest()
            #else
            self.flushPendingChanges(forceTombstones: true)
            self.requestFullSync()
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let payload = applicationContext
        Task { @MainActor [weak self] in
            self?.handleIncoming(payload)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = userInfo
        Task { @MainActor [weak self] in
            self?.handleIncoming(payload)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard let batchString = userInfoTransfer.userInfo[WatchSyncEnvelope.batchIDKey] as? String,
              let batchID = UUID(uuidString: batchString) else { return }
        let transferError = error
        Task { @MainActor [weak self] in
            self?.completeBatch(batchID, error: transferError)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = message
        Task { @MainActor [weak self] in
            guard let self else { return }
            if payload["requestSync"] as? Bool == true {
                self.handleSyncRequest()
            }
            self.handleIncoming(payload)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = isReachable
            if isReachable {
                self?.flushPendingChanges()
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        AppLogger.watch.debug("Session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        AppLogger.watch.debug("Session deactivated, reactivating...")
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let isPaired = session.isPaired
        let isReachable = session.isReachable
        let installed = session.isWatchAppInstalled
        Task { @MainActor [weak self] in
            self?.isPaired = isPaired
            self?.isReachable = isReachable
            if isPaired && installed {
                self?.handleSyncRequest()
            }
        }
    }
    #endif
}
#endif
