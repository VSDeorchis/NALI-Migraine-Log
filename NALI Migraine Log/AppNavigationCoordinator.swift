//
//  AppNavigationCoordinator.swift
//  NALI Migraine Log
//
//  Lightweight app-level navigation bus.
//
//  App Intents (Siri / Shortcuts / Spotlight) run outside the SwiftUI
//  view tree, so they need a way to ask the running app to surface a
//  particular screen. Rather than thread a URL deep-link through
//  `onOpenURL`, we publish intent requests on this shared object and let
//  the app root observe them. Today its only job is "open the New Entry
//  screen", driven by `OpenNewEntryIntent`.
//
//  Kept deliberately tiny and platform-scoped (`#if os(iOS)`): the macOS
//  app exposes the equivalent action through its menu-bar commands, and
//  the Watch app drives its own navigation, so neither needs this.
//

#if os(iOS)

import Foundation
import Combine

/// Observable bridge between out-of-process App Intents and the SwiftUI
/// app root. Mutate on the main thread only — intent `perform()` bodies
/// that touch it are annotated `@MainActor`, which satisfies that.
final class AppNavigationCoordinator: ObservableObject {
    static let shared = AppNavigationCoordinator()

    /// Drives a New Entry sheet at the app root. Set to `true` to request
    /// it; the root view binds a sheet to this and flips it back to
    /// `false` on dismiss.
    @Published var showNewEntry = false

    private init() {}

    /// Request that the app present the New Migraine entry screen. Safe to
    /// call from an App Intent's `@MainActor perform()`.
    func requestNewEntry() {
        showNewEntry = true
    }
}

#endif
