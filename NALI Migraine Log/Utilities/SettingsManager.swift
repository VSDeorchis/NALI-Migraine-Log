import SwiftUI

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var useICloudSync: Bool {
        didSet {
            UserDefaults.standard.set(useICloudSync, forKey: "useICloudSync")
        }
    }
    
    @Published var colorScheme: ColorSchemePreference {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: "colorScheme")
        }
    }
    
    enum ColorSchemePreference: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
    
    init() {
        self.useICloudSync = UserDefaults.standard.bool(forKey: "useICloudSync")
        self.colorScheme = ColorSchemePreference(rawValue: 
            UserDefaults.standard.string(forKey: "colorScheme") ?? "System"
        ) ?? .system
    }
} 