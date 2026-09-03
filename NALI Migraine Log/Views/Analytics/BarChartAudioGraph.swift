import Accessibility
import SwiftUI

/// Audio Graph description for a single-series bar chart whose x axis is a
/// list of categories (months, triggers, pain levels…). Attach with
/// `.accessibilityChartDescriptor(_:)`; VoiceOver then offers "Chart
/// Details" with a sonified sweep and a per-bar summary. Only the values
/// already drawn on screen are exposed — never notes or locations.
struct BarChartAudioGraph: AXChartDescriptorRepresentable {
    struct Bar {
        let label: String
        let value: Double
    }

    var title: String
    var xAxisTitle: String
    var yAxisTitle: String
    var bars: [Bar]
    var summary: String? = nil
    /// Spoken after each value, e.g. "migraines" → "3 migraines".
    var valueUnit: String? = nil
    var fractionDigits = 0

    init(
        title: String,
        xAxisTitle: String,
        yAxisTitle: String,
        bars: [Bar],
        summary: String? = nil,
        valueUnit: String? = nil,
        fractionDigits: Int = 0
    ) {
        self.title = title
        self.xAxisTitle = xAxisTitle
        self.yAxisTitle = yAxisTitle
        self.bars = bars
        self.summary = summary
        self.valueUnit = valueUnit
        self.fractionDigits = fractionDigits
    }

    /// Convenience for the common "(category, count)" shape.
    init(
        title: String,
        xAxisTitle: String,
        yAxisTitle: String,
        counts: [(String, Int)],
        summary: String? = nil,
        valueUnit: String? = "migraines"
    ) {
        self.init(
            title: title,
            xAxisTitle: xAxisTitle,
            yAxisTitle: yAxisTitle,
            bars: counts.map { Bar(label: $0.0, value: Double($0.1)) },
            summary: summary,
            valueUnit: valueUnit
        )
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let upper = max(bars.map(\.value).max() ?? 0, 1)
        let digits = fractionDigits
        let unit = valueUnit

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: xAxisTitle,
            categoryOrder: bars.map(\.label)
        )

        let yAxis = AXNumericDataAxisDescriptor(
            title: yAxisTitle,
            range: 0...upper,
            gridlinePositions: []
        ) { value in
            let number = value.formatted(.number.precision(.fractionLength(digits)))
            guard let unit, !unit.isEmpty else { return number }
            return "\(number) \(unit)"
        }

        let series = AXDataSeriesDescriptor(
            name: yAxisTitle,
            isContinuous: false,
            dataPoints: bars.map { AXDataPoint(x: $0.label, y: $0.value) }
        )

        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
