import SwiftUI
import UIKit

struct NavigationConfig {
    static func style(for device: UIUserInterfaceIdiom) -> NavigationBarItem.TitleDisplayMode {
        switch device {
        case .pad:
            return .large
        default:
            return .automatic
        }
    }
} 