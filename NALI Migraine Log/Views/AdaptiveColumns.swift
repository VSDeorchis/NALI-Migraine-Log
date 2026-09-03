//
//  AdaptiveColumns.swift
//  NALI Migraine Log
//
//  Width-based layout decisions for the iPad two-column destinations.
//  `horizontalSizeClass == .regular` alone is not enough: an iPad in
//  a 50/50 Split View, or the detail column of a `NavigationSplitView`
//  with its sidebar open, still reports `.regular` while offering only
//  a few hundred points of width. These helpers let a view fall back
//  to its single-column (iPhone) layout when the measured width can't
//  fit a master column plus a useful detail pane.
//

import SwiftUI

enum AdaptiveColumns {
    /// Below this width a master + detail pair would leave the detail
    /// pane narrower than an iPhone, so views use their compact layout.
    static let twoColumnMinimumWidth: CGFloat = 700

    /// Preferred master-column width for a given total width.
    static func masterWidth(for totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return 380 }
        return min(380, max(300, totalWidth * 0.42))
    }

    /// A width of 0 means "not measured yet" and defers to the size class
    /// so the first frame doesn't flash the compact layout on iPad.
    static func usesTwoColumns(sizeClass: UserInterfaceSizeClass?, width: CGFloat) -> Bool {
        sizeClass == .regular && (width == 0 || width >= twoColumnMinimumWidth)
    }
}

extension View {
    /// Reports the view's width into `width` without affecting layout.
    func measureWidth(into width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width.wrappedValue = newWidth
        }
    }
}
