//
//  AppLogger.swift
//  NALI Migraine Log
//
//  Thin wrapper around `os.Logger` so the rest of the codebase never has to
//  remember the subsystem string and so we can change the logging backend
//  (Sentry, file-based, etc.) in exactly one place if we ever need to.
//
//  Why categorize?
//    • Console.app and `log stream --predicate` can filter by category, which
//      makes debugging a specific subsystem (Core Data sync, weather refresh,
//      ML training, etc.) far easier than scrolling through one giant feed.
//    • Each category gets its own privacy/redaction defaults — handy for the
//      health-data subsystems that should never leak PII to logs.
//
//  Privacy reminder:
//    `os.Logger` redacts interpolated values by default in release builds.
//    To opt a value into being logged in cleartext, write it as
//    `\(value, privacy: .public)`. Anything that touches user-entered text,
//    notes, or health data should NEVER be marked `.public`.
//

import Foundation
import os

enum AppLogger {
    /// Bundle identifier serves as the subsystem so logs from this app are
    /// trivially filterable in Console.app.
    private static let subsystem: String = Bundle.main.bundleIdentifier
        ?? "com.nali.migrainelog"

    static let coreData     = Logger(subsystem: subsystem, category: "core-data")
    static let sync         = Logger(subsystem: subsystem, category: "sync")
    static let watch        = Logger(subsystem: subsystem, category: "watch-connectivity")
    static let weather      = Logger(subsystem: subsystem, category: "weather")
    static let health       = Logger(subsystem: subsystem, category: "healthkit")
    static let location     = Logger(subsystem: subsystem, category: "location")
    static let prediction   = Logger(subsystem: subsystem, category: "prediction")
    static let migration    = Logger(subsystem: subsystem, category: "migration")
    static let review       = Logger(subsystem: subsystem, category: "review-prompt")
    static let ui           = Logger(subsystem: subsystem, category: "ui")
    static let general      = Logger(subsystem: subsystem, category: "general")
}
