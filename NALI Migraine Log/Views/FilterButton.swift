import SwiftUI

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color(.systemBlue) : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : Color(.label))
                .cornerRadius(8)
        }
    }
} 