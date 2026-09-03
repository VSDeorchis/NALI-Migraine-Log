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

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        Feature(
            symbol: "mic.fill",
            title: "Hands-free logging",
            detail: "Just say \u{201C}Hey Siri, log a migraine in Headway\u{201D} \u{2014} optionally with a pain level \u{2014} and it\u{2019}s saved instantly, no tapping."
        ),
        Feature(
            symbol: "square.and.pencil",
            title: "Open straight to a new entry",
            detail: "Say \u{201C}Open a new migraine entry in Headway\u{201D} to jump right to the full form when you want to add details."
        ),
        Feature(
            symbol: "applewatch",
            title: "Now on Apple Watch",
            detail: "Log a migraine or open a new entry with Siri right from your wrist \u{2014} even when your phone isn\u{2019}t handy."
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

            Text("Now with Siri & Apple Watch")
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
