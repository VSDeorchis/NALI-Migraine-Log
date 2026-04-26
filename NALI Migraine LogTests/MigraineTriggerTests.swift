//
//  MigraineTriggerTests.swift
//  NALI Migraine LogTests
//
//  Pure-Swift tests for the `MigraineTrigger` enum facade. No Core Data
//  dependency — these exercise the value-type contract: display names,
//  search keywords, legacy-name parsing, and case-iteration order.
//
//  These tests are the safety net for renaming a case (e.g. the historical
//  `Hormones` → `Menstrual` rename) without breaking exported CSVs, search,
//  or any user data persisted under a legacy label.
//

import Testing
@testable import NALI_Migraine_Log

@Suite("MigraineTrigger facade")
struct MigraineTriggerTests {

    @Test("Every case has a non-empty displayName")
    func displayNamesAreNonEmpty() {
        for trigger in MigraineTrigger.allCases {
            #expect(!trigger.displayName.isEmpty, "Empty displayName for \(trigger)")
        }
    }

    @Test("displayNames are unique across cases")
    func displayNamesAreUnique() {
        let names = MigraineTrigger.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "Duplicate displayName: \(names)")
    }

    @Test("Round-trip: init?(displayName:) recovers each case from its own displayName")
    func roundTripDisplayNames() {
        for trigger in MigraineTrigger.allCases {
            let parsed = MigraineTrigger(displayName: trigger.displayName)
            #expect(parsed == trigger, "Round-trip failed for \(trigger)")
        }
    }

    @Test("init?(displayName:) tolerates surrounding whitespace and case variants")
    func displayNameIsTolerant() {
        #expect(MigraineTrigger(displayName: "  stress  ") == .stress)
        #expect(MigraineTrigger(displayName: "STRESS") == .stress)
        #expect(MigraineTrigger(displayName: "Lack Of Sleep") == .lackOfSleep)
    }

    @Test("Legacy display name 'Hormones' still resolves to .menstrual")
    func legacyHormonesAlias() {
        #expect(MigraineTrigger(displayName: "Hormones") == .menstrual)
        #expect(MigraineTrigger(displayName: "hormones") == .menstrual)
    }

    @Test("Snake/kebab-case legacy variants resolve to their canonical case")
    func legacySnakeKebabAliases() {
        #expect(MigraineTrigger(displayName: "lack-of-sleep") == .lackOfSleep)
        #expect(MigraineTrigger(displayName: "lack_of_sleep") == .lackOfSleep)
        #expect(MigraineTrigger(displayName: "screen-time") == .screenTime)
        #expect(MigraineTrigger(displayName: "screen_time") == .screenTime)
    }

    @Test("init?(displayName:) returns nil for empty / unknown input")
    func unknownDisplayNameReturnsNil() {
        #expect(MigraineTrigger(displayName: "") == nil)
        #expect(MigraineTrigger(displayName: "   ") == nil)
        #expect(MigraineTrigger(displayName: "definitely not a trigger") == nil)
    }

    @Test("Every case has at least one search keyword that resolves back via the search")
    func searchKeywordsAreNonEmptyAndLowercase() {
        for trigger in MigraineTrigger.allCases {
            let keywords = trigger.searchKeywords
            #expect(!keywords.isEmpty, "No keywords for \(trigger)")
            for keyword in keywords {
                #expect(keyword == keyword.lowercased(), "Keyword '\(keyword)' for \(trigger) is not lowercase")
                #expect(!keyword.isEmpty, "Empty keyword for \(trigger)")
            }
        }
    }

    @Test("Menstrual exposes both the new 'menstrual' and legacy 'hormones' search keyword")
    func menstrualSearchKeywords() {
        let keywords = MigraineTrigger.menstrual.searchKeywords
        #expect(keywords.contains("menstrual"))
        #expect(keywords.contains("hormones"), "Legacy 'hormones' search keyword must keep matching")
    }

    @Test("allCases enumeration order is locked — exporters depend on it")
    func allCasesOrderIsStable() {
        // CSV exports column-align trigger booleans against this order. If a
        // case is added/removed/reordered, this test must be updated *and*
        // the CSV header in `SettingsView.exportToCSV()` updated in lockstep.
        let expected: [MigraineTrigger] = [
            .stress, .lackOfSleep, .dehydration, .weather, .menstrual,
            .alcohol, .caffeine, .food, .exercise, .screenTime, .other
        ]
        #expect(MigraineTrigger.allCases == expected)
    }
}
