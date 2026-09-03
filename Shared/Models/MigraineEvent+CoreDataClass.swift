import Foundation
import CoreData

enum MigraineEntityError: Error {
    case missingContext
    case invalidName(String)
}

@objc(MigraineEvent)
public class MigraineEvent: NSManagedObject {
    /// Stamps `modifiedAt` on every local edit. A caller that sets
    /// `modifiedAt` itself (sync applying a counterpart's revision) wins, so
    /// the remote timestamp is preserved rather than replaced with "now".
    public override func willSave() {
        super.willSave()
        guard !isDeleted else { return }
        let changed = changedValues()
        guard !changed.isEmpty, changed["modifiedAt"] == nil else { return }
        setPrimitiveValue(Date(), forKey: "modifiedAt")
    }

    /// Revision used for last-writer-wins. Entries written before the
    /// attribute existed report `.distantPast` so they never beat a real edit.
    var revision: Date {
        modifiedAt ?? .distantPast
    }
}
