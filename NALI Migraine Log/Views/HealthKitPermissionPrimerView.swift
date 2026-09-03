//
//  HealthKitPermissionPrimerView.swift
//  NALI Migraine Log
//
//  A "primer" sheet shown BEFORE Apple's `HKHealthStore.requestAuthorization`
//  sheet so the user actually understands what's about to be asked of
//  them.
//
//  ──────────────────────────────────────────────────────────────────────
//  WHY THIS EXISTS
//  ──────────────────────────────────────────────────────────────────────
//  Apple's permission sheet shows every requested category as a row in a
//  scrollable list. We currently ask for 7 categories (1 write +
//  6 reads — see `HealthKitManager.readTypes` and `writeTypes`). On any
//  iPhone smaller than a Pro Max, the top ~2 rows fit above the fold
//  and the remaining 5 are below — many users tap "Allow" or "Don't
//  Allow" on the visible rows and dismiss without scrolling, leaving
//  most of the features that depend on HealthKit silently broken.
//
//  The system sheet's UI is not customizable. We cannot:
//      • reorder the rows
//      • annotate them
//      • re-prompt for a denied category
//
//  We CAN show our own UI before the sheet fires, which is what this
//  view does. It enumerates every category we're about to ask for in
//  plain English, explains why each one is useful, tells the user the
//  next screen will scroll and that they should review all of it, and
//  reassures them that everything stays on device.
//
//  ──────────────────────────────────────────────────────────────────────
//  CALL SITES
//  ──────────────────────────────────────────────────────────────────────
//  The primer is currently presented from:
//      • `NewMigraineView` (the first migraine the user logs)
//      • `SettingsView` → Apple Health → "Connect Apple Health"
//
//  It is intentionally NOT presented from `MigraineRiskView`, which has
//  its own bespoke primer screen with risk-prediction-specific framing.
//
//  ──────────────────────────────────────────────────────────────────────
//  WHAT HAPPENS AFTER THE BUTTONS
//  ──────────────────────────────────────────────────────────────────────
//  This view is intentionally dumb: it takes two closures (`onContinue`
//  and `onSkip`) and dismisses itself afterward. The hosting view is
//  responsible for actually invoking `HealthKitManager.requestAuthorization`
//  or recording the skip. This keeps the primer reusable from anywhere
//  without baking in a specific post-primer flow.
//

#if os(iOS)

import SwiftUI

struct HealthKitPermissionPrimerView: View {

    /// Invoked when the user taps "Continue". The host view should
    /// call `HealthKitManager.shared.requestAuthorization()` here to
    /// trigger Apple's permission sheet.
    var onContinue: () -> Void

    /// Invoked when the user taps "Not Now" / dismisses without
    /// continuing. The host view should call
    /// `HealthKitManager.shared.markAuthorizationRequested()` if it
    /// wants to suppress further auto-prompts; otherwise the primer
    /// will re-appear next time the host view's `.task` runs.
    var onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Hero
                    VStack(spacing: 12) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.pink)
                            .accessibilityHidden(true)

                        Text("Connect Apple Health")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Headway can use Apple Health to enrich every migraine you log and improve risk predictions. Everything stays on your device — nothing is sent to a server.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 12)

                    // Heads-up about the system sheet itself. This is
                    // the entire point of the primer — set expectations
                    // for the scrollable list of toggles the user is
                    // about to see.
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text("On the next screen, Apple will show a list of toggles. **Please scroll all the way down** and turn on each item you're comfortable sharing — Apple's screen does not fit on most iPhones without scrolling.")
                                .font(.subheadline)
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Read permissions list
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What we read")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)

                        permissionRow(
                            icon: "moon.zzz.fill",
                            tint: .indigo,
                            title: "Sleep",
                            detail: "Last night's duration, to spot \"too little\" or \"too much\" patterns."
                        )
                        permissionRow(
                            icon: "waveform.path.ecg",
                            tint: .teal,
                            title: "Heart Rate Variability",
                            detail: "An early-warning signal for autonomic stress."
                        )
                        permissionRow(
                            icon: "heart.fill",
                            tint: .red,
                            title: "Resting Heart Rate",
                            detail: "Trends that often precede migraine episodes."
                        )
                        permissionRow(
                            icon: "figure.walk",
                            tint: .green,
                            title: "Step Count",
                            detail: "Activity changes around the days you log a migraine."
                        )
                        permissionRow(
                            icon: "drop.fill",
                            tint: .pink,
                            title: "Menstrual Cycle",
                            detail: "Optional — lets Analytics correlate migraines with cycle phase."
                        )
                    }
                    .padding(.horizontal, 4)

                    // Write permissions list. Visually separated so the
                    // user doesn't conflate "Headway reads X" with
                    // "Headway writes X".
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What we write")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)

                        permissionRow(
                            icon: "brain.head.profile",
                            tint: .purple,
                            title: "Headache Entries",
                            detail: "Every migraine you log here can also appear in Apple Health under Browse → Symptoms → Headache. Off by default."
                        )
                    }
                    .padding(.horizontal, 4)

                    // Privacy reminder. Apple-style "all stays on device"
                    // framing.
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("You can decline any item now and change your mind later in iOS Settings → Privacy → Health → Headway.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    // Actions
                    VStack(spacing: 10) {
                        Button {
                            onContinue()
                            dismiss()
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityHint("Opens Apple's permission sheet. Scroll all the way down on that screen to see every toggle.")

                        Button("Not Now") {
                            onSkip()
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Row helper

    private func permissionRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .scaledFont(size: 18, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Primer") {
    HealthKitPermissionPrimerView(onContinue: {}, onSkip: {})
}

#endif
