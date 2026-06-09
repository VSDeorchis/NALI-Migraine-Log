//
//  WatchNavigationCoordinator.swift
//  NALI Migraine Log Watch App Watch App
//
//  Lightweight bus that lets an out-of-process App Intent (Siri /
//  Shortcuts on the Watch) ask the running SwiftUI hierarchy to present
//  the New Entry screen. App Intents can't toggle a view's `@State`
//  directly, so the intent flips `showNewEntry` here and the watch log
//  view observes it. Mirrors `AppNavigationCoordinator` on iOS.
//

#if os(watchOS)

import Foundation
import Combine

final class WatchNavigationCoordinator: ObservableObject {
    static let shared = WatchNavigationCoordinator()

    @Published var showNewEntry = false

    private init() {}

    @MainActor
    func requestNewEntry() {
        showNewEntry = true
    }
}

#endif
