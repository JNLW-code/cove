import AppKit
import Carbon

/// Global shortcuts for Allow and Deny, registered only while a card is showing. Carbon hot keys need no
/// Accessibility permission. Defaults ⌃⌥Y / ⌃⌥N; stored in UserDefaults as key code + modifiers.
@MainActor
final class HotKeys {
    struct Combo: Equatable, Sendable {
        var keyCode: UInt32
        var modifiers: UInt32   // Carbon: controlKey, optionKey, cmdKey, shiftKey

        var display: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            return s + Self.keyName(keyCode)
        }

        static func keyName(_ code: UInt32) -> String {
            let names: [UInt32: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
                                           12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
                                           22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P",
                                           37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space", 36: "⏎", 53: "⎋"]
            return names[code] ?? "key \(code)"
        }
    }

    static let ctrlOpt = UInt32(controlKey | optionKey)
    static let ctrlCmd = UInt32(controlKey | cmdKey)
    static let ctrlShift = UInt32(controlKey | shiftKey)
    static let defaultAllow = Combo(keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(controlKey | optionKey))
    static let defaultDeny = Combo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey))

    nonisolated(unsafe) private static weak var shared: HotKeys?
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private let onAllow: () -> Void
    private let onDeny: () -> Void

    init(onAllow: @escaping () -> Void, onDeny: @escaping () -> Void) {
        self.onAllow = onAllow
        self.onDeny = onDeny
        Self.shared = self
    }

    static func load(_ key: String, default combo: Combo) -> Combo {
        let d = UserDefaults.standard
        guard let dict = d.dictionary(forKey: key), let code = dict["key"] as? Int, let mods = dict["mods"] as? Int else { return combo }
        return Combo(keyCode: UInt32(code), modifiers: UInt32(mods))
    }

    static func save(_ combo: Combo, for key: String) {
        UserDefaults.standard.set(["key": Int(combo.keyCode), "mods": Int(combo.modifiers)], forKey: key)
    }

    var allow: Combo { Self.load("allowKey", default: Self.defaultAllow) }
    var deny: Combo { Self.load("denyKey", default: Self.defaultDeny) }

    /// Registers both shortcuts. Safe to call again; it re-registers.
    func register() {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                let which = id.id
                Task { @MainActor in HotKeys.shared?.fired(which) }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        for (index, combo) in [allow, deny].enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x434F_5645), id: UInt32(index + 1)) // "COVE"
            if RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            } else {
                Log.app.error("Could not register shortcut \(combo.display, privacy: .public)")
            }
        }
    }

    func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
    }

    private func fired(_ id: UInt32) {
        if id == 1 { onAllow() } else if id == 2 { onDeny() }
    }
}
