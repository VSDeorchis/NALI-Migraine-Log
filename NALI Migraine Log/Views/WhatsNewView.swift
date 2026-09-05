//
//  WhatsNewView.swift
//  NALI Migraine Log
//
//  One-time "What's New" announcement shown after an update that adds a
//  user-facing feature. Presented from the app root via `WhatsNew`
//  gating (see `WhatsNew.swift`). Styled to match the splash screen:
//  the shared steel-blue `AnimatedGradientBackground` behind a frosted
//  glass card, Optima type, white text.
//

import SwiftUI

struct WhatsNewView: View {
    /// Called when the user dismisses the announcement. The caller is
    /// responsible for marking the release seen + tearing down the
    /// presentation.
    let onDismiss: () -> Void

    @ObservedObject private var healthKit = HealthKitManager.shared

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
        var cycleRelated = false
    }

    /// Cycle-aware insights are never offered when Health lists the user
    /// as male, so the announcement omits that row for them as well.
    private var features: [Feature] {
        Self.allFeatures.filter { !$0.cycleRelated || healthKit.cycleEligibility != .excluded }
    }

    private static let allFeatures: [Feature] = [
        Feature(
            symbol: "applewatch",
            title: "Three-tap logging on Apple Watch",
            detail: "Pain level, your usual triggers and symptoms, save. Entries appear on your iPhone right away, and edits on either device stay in sync."
        ),
        Feature(
            symbol: "drop.fill",
            title: "Cycle-aware insights (optional)",
            detail: "If you track your cycle in Apple Health, entries near the start of a period are tagged, your risk forecast accounts for it, and Statistics shows how much more likely migraines are around your period. Turn it on in Settings \u{203A} Apple Health \u{2014} cycle data never leaves your iPhone.",
            cycleRelated: true
        ),
        Feature(
            symbol: "chart.xyaxis.line",
            title: "A redesigned Statistics dashboard",
            detail: "Migraine days up front, with trends against your previous period, median duration, acute-medication days, symptom and weekday patterns, and a scrollable 12-month chart you can tap to explore."
        ),
        Feature(
            symbol: "slider.horizontal.3",
            title: "Settings, reorganized",
            detail: "Data & Privacy, Integrations, Notifications, Appearance, and About \u{2014} with the status of each permission and a one-tap link to fix it."
        ),
        Feature(
            symbol: "pills.fill",
            title: "Clearer medications",
            detail: "Listed as generic (Brand), with the ones you use most pinned to the top. A gentle tap confirms every save, and half-finished entries are kept as drafts."
        ),
        Feature(
            symbol: "chart.bar.xaxis",
            title: "Charts you can hear",
            detail: "Every chart supports VoiceOver Audio Graphs, empty screens explain what\u{2019}s coming, and the whole app respects your preferred text size."
        ),
        Feature(
            symbol: "lock.shield.fill",
            title: "Privacy and reliability",
            detail: "Sturdier weather and location lookups, stronger on-device protection for exports and prediction data, and \u{201C}Delete All Data\u{201D} now clears everything Headway created."
        )
    ]

    var body: some View {
        ZStack {
            // Static steel-blue brand gradient (animationPhase 0 keeps the
            // blue end of the splash palette without driving a timer here).
            AnimatedGradientBackground(animationPhase: 0)
                .ignoresSafeArea()

            // The card scrolls if it's taller than the screen, but
            // centers vertically when it fits. Pinning the content's
            // minHeight to the viewport lets the surrounding Spacers
            // balance the card in the middle; the button stays at the
            // bottom of that stack.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 0)

                        VStack(spacing: 22) {
                            header

                            VStack(spacing: 18) {
                                ForEach(features) { feature in
                                    featureRow(feature)
                                }
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 30)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
                        )

                        Spacer(minLength: 0)

                        dismissButton
                    }
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
                .accessibilityHidden(true)

            Text("What\u{2019}s New")
                .font(.custom("Optima-Bold", size: 32, relativeTo: .largeTitle))
                .foregroundStyle(.white)

            Text(healthKit.cycleEligibility == .excluded
                 ? "Faster Watch logging, redesigned Statistics & more"
                 : "Faster Watch logging, cycle-aware insights, redesigned Statistics & more")
                .font(.custom("Optima-Regular", size: 18, relativeTo: .title3))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
        }
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: feature.symbol)
                    .scaledFont(size: 20, weight: .semibold)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.custom("Optima-Bold", size: 18, relativeTo: .headline))
                    .foregroundStyle(.white)
                Text(feature.detail)
                    .font(.custom("Optima-Regular", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Got It")
                .font(.custom("Optima-Bold", size: 18, relativeTo: .headline))
                .foregroundStyle(Color(red: 68/255, green: 130/255, blue: 180/255))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WhatsNewView(onDismiss: {})
}
