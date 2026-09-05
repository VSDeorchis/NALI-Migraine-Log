//
//  AccessibilitySemanticsTests.swift
//  NALI Migraine LogTests
//
//  Colour-coded analytics surfaces carry a second, non-colour channel
//  (glyph or wording) so meaning survives Differentiate Without Colour and
//  monochrome rendering.
//

import Testing
@testable import NALI_Migraine_Log

@Suite("Accessibility semantics")
struct AccessibilitySemanticsTests {

    @Test("Every severity bucket has a distinct glyph and title")
    func severityBucketsAreDistinguishableWithoutColor() {
        let symbols = SeverityBucket.allCases.map(\.symbolName)
        let titles = SeverityBucket.allCases.map(\.title)

        #expect(Set(symbols).count == SeverityBucket.allCases.count)
        #expect(Set(titles).count == SeverityBucket.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test("Severity glyphs are ordered so fill grows with pain")
    func severityGlyphOrdering() {
        #expect(SeverityBucket.bucket(for: 2)?.symbolName == "circle")
        #expect(SeverityBucket.bucket(for: 5)?.symbolName == "circle.lefthalf.filled")
        #expect(SeverityBucket.bucket(for: 8)?.symbolName == "circle.fill")
        #expect(SeverityBucket.bucket(for: 10)?.symbolName == "exclamationmark.circle.fill")
    }

    @Test("Trend sentiment exposes a glyph and wording only when it carries meaning")
    func trendSentimentSemantics() {
        #expect(TrendSentiment.favorable.symbolName == "checkmark")
        #expect(TrendSentiment.favorable.accessibilityDescription == "better")
        #expect(TrendSentiment.unfavorable.symbolName == "exclamationmark")
        #expect(TrendSentiment.unfavorable.accessibilityDescription == "worse")
        #expect(TrendSentiment.neutral.symbolName == nil)
        #expect(TrendSentiment.neutral.accessibilityDescription == nil)
    }
}
