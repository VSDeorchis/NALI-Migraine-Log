//
//  MacDailyCheckInView.swift
//  NALI Migraine Log macOS
//
//  macOS-compatible daily check-in for stress, hydration, and caffeine.
//

import SwiftUI

struct MacDailyCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var stressLevel: Int = 3
    @State private var hydrationLevel: Int = 3
    @State private var caffeineIntake: Int = 1
    @State private var hasExistingCheckIn = false
    
    var onComplete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
                
                Text("How are you feeling today?")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("This information helps improve prediction accuracy.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Stress
            checkInSection(
                title: "Stress Level",
                icon: "brain.head.profile",
                color: .orange,
                value: $stressLevel,
                labels: ["Relaxed", "Mild", "Moderate", "High", "Severe"],
                description: stressDescription
            )
            
            // Hydration
            checkInSection(
                title: "Hydration",
                icon: "drop.fill",
                color: .blue,
                value: $hydrationLevel,
                labels: ["Very Low", "Low", "Moderate", "Good", "Excellent"],
                description: hydrationDescription
            )
            
            // Caffeine
            HStack {
                Label("Caffeine Intake", systemImage: "cup.and.saucer.fill")
                    .font(.headline)
                    .foregroundColor(.brown)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        if caffeineIntake > 0 { caffeineIntake -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.brown)
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(caffeineIntake)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .frame(width: 40)
                    
                    Button {
                        if caffeineIntake < 10 { caffeineIntake += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.brown)
                    }
                    .buttonStyle(.plain)
                    
                    Text(caffeineIntake == 1 ? "cup" : "cups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                }
            }
            
            Spacer()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button {
                    saveCheckIn()
                } label: {
                    Text(hasExistingCheckIn ? "Update Check-in" : "Save Check-in")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 400, idealWidth: 500, minHeight: 450, idealHeight: 550)
        .onAppear { loadExisting() }
    }
    
    // MARK: - Section
    
    private func checkInSection(
        title: String,
        icon: String,
        color: Color,
        value: Binding<Int>,
        labels: [String],
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(color)
            
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        value.wrappedValue = level
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(level)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(labels[level - 1])
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(value.wrappedValue == level
                                      ? color.opacity(0.2)
                                      : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(value.wrappedValue == level
                                        ? color
                                        : Color.clear, lineWidth: 2)
                        )
                        .foregroundColor(value.wrappedValue == level ? color : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Descriptions
    
    private var stressDescription: String {
        switch stressLevel {
        case 1: return "Feeling calm and relaxed."
        case 2: return "Mild stress, manageable."
        case 3: return "Moderate stress level."
        case 4: return "High stress — consider relaxation techniques."
        case 5: return "Severe stress — this significantly increases migraine risk."
        default: return ""
        }
    }
    
    private var hydrationDescription: String {
        switch hydrationLevel {
        case 1: return "Very low hydration — drink water now."
        case 2: return "Below recommended hydration."
        case 3: return "Moderate hydration."
        case 4: return "Good hydration level."
        case 5: return "Excellent hydration — great job!"
        default: return ""
        }
    }
    
    // MARK: - Persistence
    
    private func loadExisting() {
        if let existing = DailyCheckInData.loadToday() {
            stressLevel = existing.stressLevel ?? 3
            hydrationLevel = existing.hydrationLevel ?? 3
            caffeineIntake = existing.caffeineIntake ?? 1
            hasExistingCheckIn = true
        }
    }
    
    private func saveCheckIn() {
        let checkIn = DailyCheckInData(
            stressLevel: stressLevel,
            hydrationLevel: hydrationLevel,
            caffeineIntake: caffeineIntake,
            date: Date()
        )
        checkIn.save()
        onComplete?()
        dismiss()
    }
}
