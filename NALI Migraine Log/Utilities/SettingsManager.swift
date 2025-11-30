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
    
    @Published var temperatureUnit: TemperatureUnit {
        didSet {
            UserDefaults.standard.set(temperatureUnit.rawValue, forKey: "temperatureUnit")
        }
    }
    
    @Published var pressureUnit: PressureUnit {
        didSet {
            UserDefaults.standard.set(pressureUnit.rawValue, forKey: "pressureUnit")
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
    
    enum TemperatureUnit: String, CaseIterable {
        case fahrenheit = "Fahrenheit"
        case celsius = "Celsius"
        
        var symbol: String {
            switch self {
            case .fahrenheit: return "°F"
            case .celsius: return "°C"
            }
        }
    }
    
    enum PressureUnit: String, CaseIterable {
        case mmHg = "mmHg"
        case hPa = "hPa"
        
        var symbol: String {
            return self.rawValue
        }
    }
    
    init() {
        self.useICloudSync = UserDefaults.standard.bool(forKey: "useICloudSync")
        self.colorScheme = ColorSchemePreference(rawValue: 
            UserDefaults.standard.string(forKey: "colorScheme") ?? "System"
        ) ?? .system
        self.temperatureUnit = TemperatureUnit(rawValue:
            UserDefaults.standard.string(forKey: "temperatureUnit") ?? "Fahrenheit"
        ) ?? .fahrenheit
        self.pressureUnit = PressureUnit(rawValue:
            UserDefaults.standard.string(forKey: "pressureUnit") ?? "mmHg"
        ) ?? .mmHg
    }
    
    // MARK: - Unit Conversion Helpers
    
    /// Convert temperature from Celsius (stored value) to the user's preferred unit
    func formatTemperature(_ celsius: Double) -> String {
        switch temperatureUnit {
        case .fahrenheit:
            let fahrenheit = celsius * 9/5 + 32
            return String(format: "%.0f%@", fahrenheit, temperatureUnit.symbol)
        case .celsius:
            return String(format: "%.0f%@", celsius, temperatureUnit.symbol)
        }
    }
    
    /// Convert pressure from hPa (stored value) to the user's preferred unit
    func formatPressure(_ hPa: Double) -> String {
        switch pressureUnit {
        case .mmHg:
            let mmHg = hPa * 0.75006
            return String(format: "%.1f %@", mmHg, pressureUnit.symbol)
        case .hPa:
            return String(format: "%.1f %@", hPa, pressureUnit.symbol)
        }
    }
    
    /// Convert pressure change from hPa to the user's preferred unit
    func formatPressureChange(_ hPa: Double) -> String {
        switch pressureUnit {
        case .mmHg:
            let mmHg = hPa * 0.75006
            return String(format: "%.2f %@", mmHg, pressureUnit.symbol)
        case .hPa:
            return String(format: "%.1f %@", hPa, pressureUnit.symbol)
        }
    }
    
    /// Get pressure value in user's preferred unit (for charts)
    func convertPressure(_ hPa: Double) -> Double {
        switch pressureUnit {
        case .mmHg:
            return hPa * 0.75006
        case .hPa:
            return hPa
        }
    }
    
    /// Get temperature value in user's preferred unit (for charts)
    func convertTemperature(_ celsius: Double) -> Double {
        switch temperatureUnit {
        case .fahrenheit:
            return celsius * 9/5 + 32
        case .celsius:
            return celsius
        }
    }
} 