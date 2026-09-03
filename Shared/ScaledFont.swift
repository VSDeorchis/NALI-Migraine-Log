import SwiftUI

/// Dynamic-Type-aware replacement for `.font(.system(size:weight:design:))`.
///
/// A fixed point size never follows the user's text size setting. This
/// modifier keeps the design intent (the size at the default setting) but
/// scales it with the text style whose default size is closest, so the
/// label grows and shrinks alongside the rest of the UI.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Font.TextStyle.closest(toPointSize: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// System font at `size` points (at the default text size) that scales
    /// with Dynamic Type.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}

extension Font.TextStyle {
    /// Default (Large) point size of each text style on iOS. Used only to
    /// choose which style a custom size should scale with.
    private var defaultPointSize: CGFloat {
        switch self {
        case .largeTitle:  return 34
        case .title:       return 28
        case .title2:      return 22
        case .title3:      return 20
        case .headline:    return 17
        case .body:        return 17
        case .callout:     return 16
        case .subheadline: return 15
        case .footnote:    return 13
        case .caption:     return 12
        case .caption2:    return 11
        default:           return 17
        }
    }

    static func closest(toPointSize size: CGFloat) -> Font.TextStyle {
        let candidates: [Font.TextStyle] = [
            .caption2, .caption, .footnote, .subheadline, .callout,
            .body, .title3, .title2, .title, .largeTitle
        ]
        return candidates.min { abs($0.defaultPointSize - size) < abs($1.defaultPointSize - size) } ?? .body
    }
}
