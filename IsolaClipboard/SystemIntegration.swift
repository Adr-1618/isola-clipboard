import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .automatic: "Automatico"
        case .light: "Chiaro"
        case .dark: "Scuro"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Key.maxItems) }
    }
    @Published var openAfterCopy: Bool {
        didSet { defaults.set(openAfterCopy, forKey: Key.openAfterCopy) }
    }
    @Published var closeDelaySeconds: Double {
        didSet { defaults.set(closeDelaySeconds, forKey: Key.closeDelaySeconds) }
    }
    @Published var closeOnOutsideClick: Bool {
        didSet { defaults.set(closeOnOutsideClick, forKey: Key.closeOnOutsideClick) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    @Published var ignoreConcealed: Bool {
        didSet { defaults.set(ignoreConcealed, forKey: Key.ignoreConcealed) }
    }
    @Published var ignoreTransient: Bool {
        didSet { defaults.set(ignoreTransient, forKey: Key.ignoreTransient) }
    }
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }
    @Published var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: Key.animationsEnabled) }
    }
    @Published var shortcutKeyCode: UInt32 {
        didSet { defaults.set(Int(shortcutKeyCode), forKey: Key.shortcutKeyCode) }
    }
    @Published var shortcutModifiers: UInt32 {
        didSet { defaults.set(Int(shortcutModifiers), forKey: Key.shortcutModifiers) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let maxItems = "IsolaClipboard.maxItems"
        static let openAfterCopy = "IsolaClipboard.openAfterCopy"
        static let closeDelaySeconds = "IsolaClipboard.closeDelaySeconds"
        static let closeOnOutsideClick = "IsolaClipboard.closeOnOutsideClick"
        static let showMenuBarIcon = "IsolaClipboard.showMenuBarIcon"
        static let ignoreConcealed = "IsolaClipboard.ignoreConcealed"
        static let ignoreTransient = "IsolaClipboard.ignoreTransient"
        static let theme = "IsolaClipboard.theme"
        static let animationsEnabled = "IsolaClipboard.animationsEnabled"
        static let shortcutKeyCode = "IsolaClipboard.shortcutKeyCode"
        static let shortcutModifiers = "IsolaClipboard.shortcutModifiers"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        maxItems = min(max(defaults.object(forKey: Key.maxItems) as? Int ?? 5, 1), 5)
        openAfterCopy = defaults.object(forKey: Key.openAfterCopy) as? Bool ?? false
        closeDelaySeconds = min(max(defaults.object(forKey: Key.closeDelaySeconds) as? Double ?? 2, 1), 10)
        closeOnOutsideClick = defaults.object(forKey: Key.closeOnOutsideClick) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        ignoreConcealed = defaults.object(forKey: Key.ignoreConcealed) as? Bool ?? true
        ignoreTransient = defaults.object(forKey: Key.ignoreTransient) as? Bool ?? true
        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "automatic") ?? .automatic
        animationsEnabled = defaults.object(forKey: Key.animationsEnabled) as? Bool ?? true
        shortcutKeyCode = UInt32(defaults.object(forKey: Key.shortcutKeyCode) as? Int ?? Int(kVK_Space))
        shortcutModifiers = UInt32(defaults.object(forKey: Key.shortcutModifiers) as? Int ?? Int(controlKey | optionKey))
    }

    static func shortcutDescription(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        let keyNames: [UInt32: String] = [
            UInt32(kVK_Space): "Spazio", UInt32(kVK_Return): "Invio", UInt32(kVK_Tab): "Tab",
            UInt32(kVK_Escape): "Esc", UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
            41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`"
        ]
        let key = keyNames[keyCode] ?? "Tasto \(keyCode)"
        return parts.joined() + key
    }
}

@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @Published private(set) var errorMessage: String?

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
            errorMessage = nil
        } catch {
            refreshStatus()
            errorMessage = error.localizedDescription
        }
    }

    func refresh() { refreshStatus() }

    private func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }
}

@MainActor
final class GlobalShortcutManager {
    var onActivate: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private(set) var registrationError: OSStatus?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        if handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let userData else { return OSStatus(eventNotHandledErr) }
                    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                    var hotKeyID = EventHotKeyID()
                    var actualSize = 0
                    let status = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        &actualSize,
                        &hotKeyID
                    )
                    guard status == noErr else { return status }
                    Task { @MainActor in
                        if hotKeyID.id == 1 { manager.onActivate?() }
                        if hotKeyID.id == 2 { manager.onOpenSettings?() }
                    }
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &handler
            )
            guard handlerStatus == noErr else {
                registrationError = handlerStatus
                return
            }
        }

        registrationError = registerHotKey(id: 1, keyCode: keyCode, modifiers: modifiers)
        // A second public Carbon shortcut keeps Settings reachable if the status icon is hidden.
        let settingsStatus = registerHotKey(id: 2, keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt32(controlKey | optionKey))
        if registrationError == nil { registrationError = settingsStatus }
    }

    func unregister() {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
    }

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> OSStatus? {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x49534F4C), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference { hotKeys[id] = reference; return nil }
        return status
    }
}
