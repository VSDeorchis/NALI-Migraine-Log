import Foundation
import CoreData

enum MigraineEntityError: Error {
    case missingContext
    case invalidName(String)
}

@objc(MigraineEvent)
public class MigraineEvent: NSManagedObject {
    // Core Data managed object class
    // All properties and sync methods are now in CoreDataProperties.swift
} 