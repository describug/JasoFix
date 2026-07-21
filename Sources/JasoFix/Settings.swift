import Foundation
import Combine

final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var folders: [String] {
        didSet { defaults.set(folders, forKey: "folders") }
    }

    @Published var backgroundEnabled: Bool {
        didSet {
            defaults.set(backgroundEnabled, forKey: "backgroundEnabled")
            AgentManager.apply()
        }
    }

    @Published var intervalMinutes: Int {
        didSet {
            let clamped = max(1, intervalMinutes)
            if clamped != intervalMinutes {
                intervalMinutes = clamped
                return
            }
            defaults.set(intervalMinutes, forKey: "intervalMinutes")
            AgentManager.apply()
        }
    }

    private init() {
        folders = defaults.stringArray(forKey: "folders") ?? []
        backgroundEnabled = defaults.object(forKey: "backgroundEnabled") as? Bool ?? true
        intervalMinutes = max(1, defaults.object(forKey: "intervalMinutes") as? Int ?? 5)
    }
}
