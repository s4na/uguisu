import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var overlayWindowController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkeyManager()
        setupOverlayWindow()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "uguisu")
            // Fallback if system symbol is not available
            if button.image == nil {
                button.title = "🎤"
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Overlay (⌥ + Space)", action: #selector(showOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.showOverlay()
        }
        hotkeyManager?.register()
    }

    private func setupOverlayWindow() {
        overlayWindowController = OverlayWindowController()
    }

    @objc private func showOverlay() {
        // If window is already visible, just bring it to front
        if overlayWindowController?.window?.isVisible == true {
            overlayWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        overlayWindowController?.showWindow(nil)
    }
}
