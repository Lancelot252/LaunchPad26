import Carbon.HIToolbox
import Combine
import Foundation

enum LaunchpadHotkeyPreset: String, CaseIterable, Codable, Identifiable {
    case f4
    case optionSpace
    case commandShiftL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .f4:
            return "F4"
        case .optionSpace:
            return "⌥ Space"
        case .commandShiftL:
            return "⌘⇧L"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .f4:
            return UInt32(kVK_F4)
        case .optionSpace:
            return UInt32(kVK_Space)
        case .commandShiftL:
            return UInt32(kVK_ANSI_L)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .f4:
            return 0
        case .optionSpace:
            return UInt32(optionKey)
        case .commandShiftL:
            return UInt32(cmdKey | shiftKey)
        }
    }
}

struct LaunchpadSettings: Codable, Equatable {
    var hotkeyPreset: LaunchpadHotkeyPreset = .f4
    var enableAnimations: Bool = true
    var hideOnResignActive: Bool = true
    var confirmBeforeResetLayout: Bool = true
}

final class LaunchpadSettingsStore: ObservableObject {
    static let didChangeNotification = Notification.Name("launchpad.settings.didChange")

    @Published private(set) var current: LaunchpadSettings

    private let userDefaults: UserDefaults

    private enum Keys {
        static let hotkeyPreset = "launchpad.settings.hotkeyPreset"
        static let enableAnimations = "launchpad.settings.enableAnimations"
        static let hideOnResignActive = "launchpad.settings.hideOnResignActive"
        static let confirmBeforeResetLayout = "launchpad.settings.confirmBeforeResetLayout"
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.current = LaunchpadSettingsStore.load(from: userDefaults)
    }

    func update(_ mutate: (inout LaunchpadSettings) -> Void) {
        var updated = current
        mutate(&updated)
        guard updated != current else { return }

        current = updated
        save(updated, to: userDefaults)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func reload() {
        let loaded = LaunchpadSettingsStore.load(from: userDefaults)
        guard loaded != current else { return }

        current = loaded
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func load(from userDefaults: UserDefaults) -> LaunchpadSettings {
        var settings = LaunchpadSettings()

        if let rawPreset = userDefaults.string(forKey: Keys.hotkeyPreset),
           let preset = LaunchpadHotkeyPreset(rawValue: rawPreset) {
            settings.hotkeyPreset = preset
        }

        if userDefaults.object(forKey: Keys.enableAnimations) != nil {
            settings.enableAnimations = userDefaults.bool(forKey: Keys.enableAnimations)
        }

        if userDefaults.object(forKey: Keys.hideOnResignActive) != nil {
            settings.hideOnResignActive = userDefaults.bool(forKey: Keys.hideOnResignActive)
        }

        if userDefaults.object(forKey: Keys.confirmBeforeResetLayout) != nil {
            settings.confirmBeforeResetLayout = userDefaults.bool(forKey: Keys.confirmBeforeResetLayout)
        }

        return settings
    }

    private func save(_ settings: LaunchpadSettings, to userDefaults: UserDefaults) {
        userDefaults.set(settings.hotkeyPreset.rawValue, forKey: Keys.hotkeyPreset)
        userDefaults.set(settings.enableAnimations, forKey: Keys.enableAnimations)
        userDefaults.set(settings.hideOnResignActive, forKey: Keys.hideOnResignActive)
        userDefaults.set(settings.confirmBeforeResetLayout, forKey: Keys.confirmBeforeResetLayout)
    }
}
