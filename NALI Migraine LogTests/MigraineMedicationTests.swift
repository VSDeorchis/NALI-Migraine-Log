//
//  MigraineMedicationTests.swift
//  NALI Migraine LogTests
//
//  Pure-Swift tests for the `MigraineMedication` enum facade. These cover
//  display names (short + full), search keywords, the legacy "ibuprofin"
//  spelling, and the case-iteration order that the CSV exporter relies on.
//

import Testing
@testable import NALI_Migraine_Log

@Suite("MigraineMedication facade")
struct MigraineMedicationTests {

    @Test("Every case has a non-empty short and full displayName")
    func displayNamesAreNonEmpty() {
        for med in MigraineMedication.allCases {
            #expect(!med.displayName.isEmpty, "Empty short displayName for \(med)")
            #expect(!med.fullDisplayName.isEmpty, "Empty fullDisplayName for \(med)")
        }
    }

    @Test("Short displayNames are unique across cases")
    func shortDisplayNamesAreUnique() {
        let names = MigraineMedication.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "Duplicate displayName: \(names)")
    }

    @Test("Round-trip: init?(displayName:) recovers each case from its short name")
    func roundTripShortDisplayName() {
        for med in MigraineMedication.allCases {
            let parsed = MigraineMedication(displayName: med.displayName)
            #expect(parsed == med, "Round-trip via short name failed for \(med)")
        }
    }

    @Test("Round-trip: init?(displayName:) recovers each case from its full name")
    func roundTripFullDisplayName() {
        for med in MigraineMedication.allCases {
            let parsed = MigraineMedication(displayName: med.fullDisplayName)
            #expect(parsed == med, "Round-trip via fullDisplayName failed for \(med)")
        }
    }

    @Test("init?(displayName:) tolerates the historic 'ibuprofin' misspelling")
    func legacyIbuprofinSpelling() {
        // 'ibuprofin' is the on-disk Core Data attribute spelling; users with
        // older exports / clipboards may still send this exact token. The
        // facade must keep accepting it forever to avoid silent data loss.
        #expect(MigraineMedication(displayName: "ibuprofin") == .ibuprofin)
    }

    @Test("Whitespace and case variants resolve correctly")
    func caseAndWhitespaceTolerance() {
        #expect(MigraineMedication(displayName: "  TYLENOL  ") == .tylenol)
        #expect(MigraineMedication(displayName: "Naproxen") == .naproxen)
    }

    @Test("Empty / unknown input returns nil")
    func unknownInputReturnsNil() {
        #expect(MigraineMedication(displayName: "") == nil)
        #expect(MigraineMedication(displayName: "   ") == nil)
        #expect(MigraineMedication(displayName: "definitely not a med") == nil)
    }

    @Test("Search keywords are non-empty, lowercase, and include the short displayName")
    func searchKeywordsContract() {
        for med in MigraineMedication.allCases {
            let keywords = med.searchKeywords
            #expect(!keywords.isEmpty, "No keywords for \(med)")
            for keyword in keywords {
                #expect(keyword == keyword.lowercased(), "Keyword '\(keyword)' for \(med) is not lowercase")
                #expect(!keyword.isEmpty, "Empty keyword for \(med)")
            }
            #expect(keywords.contains(med.displayName.lowercased()), "Short displayName must be a search keyword for \(med)")
        }
    }

    @Test("Brand-name medications expose their generic name as a search keyword")
    func brandToGenericKeywords() {
        // Each tuple = (case, expected generic-name keyword the search bar
        // must accept). If a generic name is renamed by the FDA / formulary,
        // update both the enum and this test in lockstep.
        let mappings: [(MigraineMedication, String)] = [
            (.tylenol,  "acetaminophen"),
            (.ubrelvy,  "ubrogepant"),
            (.nurtec,   "rimegepant"),
            (.reyvow,   "lasmiditan"),
            (.trudhesa, "dihydroergotamine"),
        ]
        for (med, generic) in mappings {
            #expect(med.searchKeywords.contains(generic),
                    "\(med) must expose '\(generic)' as a search keyword")
        }
    }
}
