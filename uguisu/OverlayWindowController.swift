import Cocoa
import SwiftUI

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

class OverlayWindowController: NSWindowController {
    convenience init() {
        let contentView = OverlayContentView()

        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.center()
        window.isMovableByWindowBackground = true

        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
    }
}

struct OverlayContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Hello World")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Press Esc to close")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 600, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
    }
}
