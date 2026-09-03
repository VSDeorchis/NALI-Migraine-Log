//
//  LaunchProgressView.swift
//  NALI Migraine Log
//
//  Status strip shown over the splash while `AppLaunchCoordinator` runs
//  one-time launch work; surfaces failures with Retry / Continue.
//

import CoreData
import SwiftUI

struct LaunchProgressView: View {
    let coordinator: AppLaunchCoordinator
    let context: NSManagedObjectContext

    var body: some View {
        VStack(spacing: 12) {
            switch coordinator.phase {
            case .pending, .ready:
                EmptyView()

            case .running(let step, _):
                ProgressView(value: coordinator.progress) {
                    Text(step)
                        .font(.footnote)
                }
                .progressViewStyle(.linear)
                .accessibilityLabel("Preparing your data: \(step)")

            case .failed(let step, let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(step) didn't finish", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your existing entries are untouched. You can retry now or continue and try again on the next launch.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Retry") {
                            Task { await coordinator.run(context: context) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Continue") {
                            Task { await coordinator.skipFailedStep(context: context) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .animation(.default, value: coordinator.phase)
    }
}
