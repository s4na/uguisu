import Cocoa
import ApplicationServices

enum TextInsertionResult {
    case success
    case accessibilityDenied
    case targetNotFound
    case insertionFailed
    case clipboardFallbackUsed
}

class TextInsertionService {
    private let queue = DispatchQueue(label: "com.uguisu.textinsertion", attributes: .concurrent)
    private var _targetApp: NSRunningApplication?
    private var _targetElement: AXUIElement?

    private var targetApp: NSRunningApplication? {
        get { queue.sync { _targetApp } }
        set { queue.sync(flags: .barrier) { _targetApp = newValue } }
    }

    private var targetElement: AXUIElement? {
        get { queue.sync { _targetElement } }
        set { queue.sync(flags: .barrier) { _targetElement = newValue } }
    }

    static let shared = TextInsertionService()

    private init() {}

    /// Capture the current focus before showing overlay
    func captureCurrentFocus() {
        targetApp = NSWorkspace.shared.frontmostApplication
        targetElement = getFocusedElement()
    }

    /// Insert text to the previously captured focus
    func insertText(_ text: String, completion: @escaping (TextInsertionResult) -> Void) {
        guard let app = targetApp else {
            completion(.targetNotFound)
            return
        }

        // Check if target app still exists
        guard !app.isTerminated else {
            completion(.targetNotFound)
            return
        }

        // Activate target app
        guard app.activate(options: .activateIgnoringOtherApps) else {
            completion(.targetNotFound)
            return
        }

        // Wait a bit for activation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.performTextInsertion(text, completion: completion)
        }
    }

    private func performTextInsertion(_ text: String, completion: @escaping (TextInsertionResult) -> Void) {
        // Try method 1: AXValue direct setting
        if let element = targetElement ?? getFocusedElement(),
           insertViaAccessibility(text, to: element) {
            completion(.success)
            return
        }

        // Try method 2: Key event simulation
        if insertViaKeyEvents(text) {
            completion(.success)
            return
        }

        // Fallback: Clipboard method
        insertViaClipboard(text) { success in
            completion(success ? .clipboardFallbackUsed : .insertionFailed)
        }
    }

    // MARK: - Method 1: Accessibility API

    private func getFocusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let element = focusedElement as? AXUIElement else {
            return nil
        }

        return element
    }

    private func insertViaAccessibility(_ text: String, to element: AXUIElement) -> Bool {
        // Check if we can write to the value attribute
        var isSettable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        )

        guard result == .success && isSettable.boolValue else {
            return false
        }

        // Get current value
        var currentValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)
        let currentText = (currentValue as? String) ?? ""

        // Get selected range to determine insertion point
        var selectedRange: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        var insertPosition = currentText.count
        var selectionLength = 0

        if let range = selectedRange,
           let axValue = range as? AXValue {
            var cfRange = CFRange()
            if AXValueGetValue(axValue, .cfRange, &cfRange) {
                insertPosition = cfRange.location
                selectionLength = cfRange.length
            }
        }

        // Build new text with safe bounds checking
        var newText = currentText
        let safeInsertPosition = min(max(0, insertPosition), newText.count)
        let safeSelectionLength = min(max(0, selectionLength), newText.count - safeInsertPosition)
        let startIndex = newText.index(newText.startIndex, offsetBy: safeInsertPosition)
        let endIndex = newText.index(startIndex, offsetBy: safeSelectionLength)
        newText.replaceSubrange(startIndex..<endIndex, with: text)

        // Set new value
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )

        return setResult == .success
    }

    // MARK: - Method 2: Key Event Simulation

    private func insertViaKeyEvents(_ text: String) -> Bool {
        // Use CGEventCreateKeyboardEvent to simulate typing
        // This is more compatible but slower and may have issues with IME

        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            guard let unicodeScalar = char.unicodeScalars.first else { continue }

            // Create key down event
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                var unicodeChar = UniChar(unicodeScalar.value)
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
                event.post(tap: .cghidEventTap)
            }

            // Create key up event
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                var unicodeChar = UniChar(unicodeScalar.value)
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unicodeChar)
                event.post(tap: .cghidEventTap)
            }

            // Small delay between characters
            usleep(1000) // 1ms
        }

        return true
    }

    // MARK: - Method 3: Clipboard Fallback

    private func insertViaClipboard(_ text: String, completion: @escaping (Bool) -> Void) {
        let pasteboard = NSPasteboard.general

        // Save original clipboard content
        let originalContent = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true), // V key
              let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            completion(false)
            return
        }

        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand

        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)

        // Restore original clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            if let original = originalContent {
                pasteboard.setString(original, forType: .string)
            }
            completion(true)
        }
    }

    /// Clear captured focus
    func clearFocus() {
        targetApp = nil
        targetElement = nil
    }
}
