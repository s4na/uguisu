import Cocoa
import Carbon.HIToolbox

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onHotkey: () -> Void

    init(onHotkey: @escaping () -> Void) {
        self.onHotkey = onHotkey
    }

    deinit {
        unregister()
    }

    func register() {
        // First unregister if already registered to prevent duplicate taps
        unregister()

        guard AXIsProcessTrusted() else {
            promptForAccessibilityPermission()
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            print("Failed to create event tap. This may happen even with Accessibility permission granted due to system restrictions.")
            showEventTapCreationFailedAlert()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        print("Hotkey registered: ⌥ + Space")
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled event - macOS can disable event taps if they're too slow
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                print("Event tap was disabled, re-enabling...")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check for Option + Space (keyCode 49 = Space)
        let isOptionPressed = flags.contains(.maskAlternate)
        let isSpaceKey = keyCode == 49

        // Make sure no other modifiers are pressed
        let noCommand = !flags.contains(.maskCommand)
        let noControl = !flags.contains(.maskControl)
        let noShift = !flags.contains(.maskShift)

        if isOptionPressed && isSpaceKey && noCommand && noControl && noShift {
            DispatchQueue.main.async { [weak self] in
                self?.onHotkey()
            }
            // Consume the event (don't pass it to other apps)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func promptForAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "uguisu needs Accessibility permission to detect global hotkeys. Please grant permission in System Preferences > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    private func showEventTapCreationFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Failed to Create Event Tap"
        alert.informativeText = "uguisu could not register the global hotkey. This may be due to system restrictions. Please try restarting the app or re-granting Accessibility permission."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
