//
//  DailyCheckInView.swift
//  NALI Migraine Log
//
//  Optional daily check-in for stress, hydration, and caffeine tracking.
//  Data is stored locally and used by the prediction engine.
//

import SwiftUI

struct DailyCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var stressLevel: Int = 3
    @State private var hydrationLevel: Int = 3
    @State private var caffeineIntake: Int = 1
    @State private var hasExistingCheckIn = false
    
    var onComplete: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    headerSection
                    
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
                    caffeinePicker
                    
                    // Save button
                    Button {
                        saveCheckIn()
                    } label: {
                        Text(hasExistingCheckIn ? "Update Check-in" : "Save Check-in")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Daily Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadExisting() }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
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
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Generic Section
    
    private func checkInSection(
        title: String,
        icon: String,
        color: Color,
        value: Binding<Int>,
        labels: [String],
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(color)
            
            // Scale buttons
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        value.wrappedValue = level
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(level)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(labels[level - 1])
                                .font(.system(size: 8))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(value.wrappedValue == level
                                      ? color.opacity(0.2)
                                      : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(value.wrappedValue == level
                                        ? color
                                        : Color.clear, lineWidth: 2)
                        )
                        .foregroundColor(value.wrappedValue == level ? color : .primary)
                    }
                }
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
    
    // MARK: - Caffeine Picker
    
    private var caffeinePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Caffeine Intake", systemImage: "cup.and.saucer.fill")
                .font(.headline)
                .foregroundColor(.brown)
            
            HStack(spacing: 12) {
                Button {
                    if caffeineIntake > 0 { caffeineIntake -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.brown)
                }
                
                VStack(spacing: 2) {
                    Text("\(caffeineIntake)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(caffeineIntake == 1 ? "cup" : "cups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 80)
                
                Button {
                    if caffeineIntake < 10 { caffeineIntake += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.brown)
                }
            }
            .frame(maxWidth: .infinity)
            
            Text(caffeineDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
    
    private var caffeineDescription: String {
        switch caffeineIntake {
        case 0: return "No caffeine today."
        case 1...2: return "Normal caffeine intake."
        case 3...4: return "Moderate to high caffeine."
        default: return "High caffeine intake — may increase migraine risk."
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
