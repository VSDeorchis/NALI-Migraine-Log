import SwiftUI
import TipKit

/// Anchored to the hero card on the Analytics dashboard until the user
/// either dismisses it or opens their first drill-down. Shown at most a
/// couple of times so it never nags.
struct AnalyticsDrillDownTip: Tip {
    var title: Text {
        Text("Tap a card for more")
    }

    var message: Text? {
        Text("Every card and number on this screen opens a detailed breakdown with charts and the entries behind it.")
    }

    var image: Image? {
        Image(systemName: "hand.tap")
    }

    var options: [Option] {
        MaxDisplayCount(2)
    }
}
