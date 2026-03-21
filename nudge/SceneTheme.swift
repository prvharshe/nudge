import SwiftUI
import Combine

// MARK: - Scene mode

enum SceneMode: String {
    case day, night
}

// MARK: - Scene manager

final class SceneManager: ObservableObject {
    @AppStorage("nudge.sceneMode") private var rawMode: String = SceneMode.day.rawValue

    var mode: SceneMode {
        get { SceneMode(rawValue: rawMode) ?? .day }
        set {
            objectWillChange.send()
            rawMode = newValue.rawValue
        }
    }

    var isDark: Bool { mode == .night }

    var preferredScheme: ColorScheme { isDark ? .dark : .light }

    func toggle() {
        mode = isDark ? .day : .night
    }
}
