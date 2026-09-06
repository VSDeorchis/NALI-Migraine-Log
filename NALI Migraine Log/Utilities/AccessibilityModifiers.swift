//
//  AccessibilityModifiers.swift
//  NALI Migraine Log
//
//  View helpers that honour the system Reduce Motion setting. Views that
//  animate a value change or roll digits use these instead of the raw
//  SwiftUI modifiers so the whole app degrades to plain state swaps when
//  the user has asked for less motion.
//

import SwiftUI

private struct MotionSafeAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct MotionSafeNumericTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .identity : .numericText())
    }
}

extension View {
    /// `animation(_:value:)` that is disabled under Reduce Motion.
    func motionSafeAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(MotionSafeAnimation(animation: animation, value: value))
    }

    /// `contentTransition(.numericText())` that falls back to an instant
    /// swap under Reduce Motion.
    func motionSafeNumericTransition() -> some View {
        modifier(MotionSafeNumericTransition())
    }
}
