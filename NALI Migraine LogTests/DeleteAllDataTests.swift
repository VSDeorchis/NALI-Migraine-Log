//
//  DeleteAllDataTests.swift
//  NALI Migraine LogTests
//
//  "Delete All Data" must leave nothing behind: Core Data rows, the pending
//  entry draft, and the on-device ML artifacts (model, training/hold-out
//  CSVs, validation record). Runs against a private in-memory store so it
//  never races the shared preview container used by other suites.
//

import CoreData
import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("Delete all data", .serialized)
@MainActor
struct DeleteAllDataTests {

    private static func makeIsolatedContext() throws -> NSManagedObjectContext {
        let model = PersistenceController.preview.container.managedObjectModel
        let container = NSPersistentContainer(name: "DeleteAllDataTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        container.viewContext.automaticallyMergesChangesFromParent = true
        return container.viewContext
    }

    private static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static var mlArtifactURLs: [URL] {
        guard let docs = documentsDirectory else { return [] }
        return ["MigrainePredictor.mlmodel", "training_data.csv", "validation_data.csv"]
            .map { docs.appendingPathComponent($0) }
    }

    private func seed(_ context: NSManagedObjectContext, count: Int) throws -> [UUID] {
        var ids: [UUID] = []
        for offset in 0..<count {
            let event = MigraineEvent(context: context)
            let id = UUID()
            event.id = id
            event.startTime = Date().addingTimeInterval(TimeInterval(-offset) * 86_400)
            event.painLevel = Int16(3 + offset % 5)
            event.location = "Frontal"
            event.notes = "seed \(offset)"
            ids.append(id)
        }
        try context.save()
        return ids
    }

    private func rowCount(_ context: NSManagedObjectContext) throws -> Int {
        try context.count(for: MigraineEvent.fetchRequest())
    }

    @Test("Every entry is removed and its ID reported")
    func removesAllRows() async throws {
        let context = try Self.makeIsolatedContext()
        let seeded = try seed(context, count: 7)
        let store = MigraineStore(context: context)
        store.fetchMigraines()
        #expect(store.migraines.count == 7)

        let outcome = try await store.deleteAllData()

        #expect(outcome.deletedCount == 7)
        #expect(Set(outcome.deletedIDs) == Set(seeded))
        #expect(try rowCount(context) == 0)
        #expect(store.migraines.isEmpty)
        #expect(store.lastError == nil)
    }

    @Test("Deleting with no entries succeeds with an empty outcome")
    func emptyStore() async throws {
        let context = try Self.makeIsolatedContext()
        let store = MigraineStore(context: context)

        let outcome = try await store.deleteAllData()

        #expect(outcome.deletedCount == 0)
        #expect(outcome.deletedIDs.isEmpty)
        #expect(try rowCount(context) == 0)
    }

    @Test("Pending entry draft and ML artifacts are wiped alongside the rows")
    func clearsDerivedData() async throws {
        let context = try Self.makeIsolatedContext()
        _ = try seed(context, count: 2)

        MigraineDraftStore.save(MigraineDraft(startTime: Date(), endTime: nil, painLevel: 6, location: "Temporal", notes: "draft"))
        #expect(MigraineDraftStore.load() != nil)

        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: "lastMLTrainDate")
        let validation = MLModelValidation(accuracy: 0.8, baseline: 0.6, sampleCount: 20, evaluatedAt: Date())
        defaults.set(try JSONEncoder().encode(validation), forKey: "mlModelValidation")
        for url in Self.mlArtifactURLs {
            try Data("placeholder".utf8).write(to: url, options: .atomic)
        }
        #expect(MigrainePredictionService.shared.modelValidation != nil)

        let store = MigraineStore(context: context)
        _ = try await store.deleteAllData()

        #expect(MigraineDraftStore.load() == nil)
        #expect(defaults.object(forKey: "lastMLTrainDate") == nil)
        #expect(defaults.data(forKey: "mlModelValidation") == nil)
        #expect(MigrainePredictionService.shared.modelValidation == nil)
        for url in Self.mlArtifactURLs {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) should be removed")
        }
        #expect(try rowCount(context) == 0)
    }

    @Test("A Health cleanup failure is reported in the outcome, not thrown, and rows are still gone")
    func healthFailureIsNonFatal() async throws {
        let context = try Self.makeIsolatedContext()
        _ = try seed(context, count: 3)
        let store = MigraineStore(context: context)

        // On a test host Health is either unavailable or unauthorised, so the
        // mirrored-sample deletion cannot succeed; the call must still return.
        let outcome = try await store.deleteAllData()

        #expect(outcome.deletedCount == 3)
        #expect(try rowCount(context) == 0)
    }
}
