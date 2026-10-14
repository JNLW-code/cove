import AppKit
import Foundation

/// Display and keyboard backlight levels. Apple silicon has no public API for either, so these go through the
/// two private frameworks Control Centre itself uses (DisplayServices, CoreBrightness), loaded at run time.
/// If a symbol is missing after a macOS update the matching slider simply disappears; nothing crashes.
@MainActor
@Observable
final class Brightness {
    private(set) var display: Float = 0
    private(set) var displayAvailable = false
    private(set) var keyboard: Float = 0
    private(set) var keyboardAvailable = false

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private var getDisplay: GetBrightness?
    private var setDisplay: SetBrightness?

    private var keyboardClient: NSObject?
    private var keyboardID: UInt64 = 0

    init() {
        loadDisplayServices()
        loadKeyboardClient()
        refresh()
    }

    func refresh() {
        if let getDisplay {
            var value: Float = 0
            if getDisplay(CGMainDisplayID(), &value) == 0 { display = value; displayAvailable = true } else { displayAvailable = false }
        }
        if let keyboardClient {
            keyboard = Self.keyboardLevel(keyboardClient, keyboardID) ?? keyboard
        }
        Log.app.debug("Brightness: display \(self.displayAvailable ? String(format: "%.2f", self.display) : "n/a", privacy: .public), keyboard \(self.keyboardAvailable ? String(format: "%.2f", self.keyboard) : "n/a", privacy: .public)")
    }

    func setDisplay(_ value: Float) {
        guard let setDisplay else { return }
        let clamped = min(1, max(0, value))
        if setDisplay(CGMainDisplayID(), clamped) == 0 { display = clamped }
    }

    func setKeyboard(_ value: Float) {
        guard let keyboardClient else { return }
        let clamped = min(1, max(0, value))
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let method = class_getInstanceMethod(type(of: keyboardClient), sel) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        if setter(keyboardClient, sel, clamped, keyboardID) { keyboard = clamped }
    }

    // MARK: Loading

    private func loadDisplayServices() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"), let set = dlsym(handle, "DisplayServicesSetBrightness") else {
            Log.app.notice("Display brightness: DisplayServices not available, slider hidden")
            return
        }
        getDisplay = unsafeBitCast(get, to: GetBrightness.self)
        setDisplay = unsafeBitCast(set, to: SetBrightness.self)
    }

    private func loadKeyboardClient() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            Log.app.notice("Keyboard backlight: CoreBrightness not available, slider hidden")
            return
        }
        let client = cls.init()
        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: idsSel), client.responds(to: NSSelectorFromString("brightnessForKeyboard:")),
              client.responds(to: NSSelectorFromString("setBrightness:forKeyboard:")),
              let ids = client.perform(idsSel)?.takeRetainedValue() as? [NSNumber], let first = ids.first else {
            Log.app.notice("Keyboard backlight: no backlit keyboard found, slider hidden")
            return
        }
        keyboardClient = client
        keyboardID = first.uint64Value
        keyboardAvailable = Self.keyboardLevel(client, keyboardID) != nil
    }

    private static func keyboardLevel(_ client: NSObject, _ id: UInt64) -> Float? {
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard let method = class_getInstanceMethod(type(of: client), sel) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let value = unsafeBitCast(method_getImplementation(method), to: Getter.self)(client, sel, id)
        return value.isFinite && value >= 0 && value <= 1 ? value : nil
    }
}
