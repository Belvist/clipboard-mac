import Cocoa
import SwiftUI
import ServiceManagement

@main
struct ClipHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var previouslyActiveApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        ClipboardManager.shared.startMonitoring()
        HotKeyManager.shared.register()

        NotificationCenter.default.addObserver(self, selector: #selector(toggleWindow), name: .toggleClipWindow, object: nil)

        if !isAccessibilityEnabled() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showAccessibilityAlert()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
        ClipboardManager.shared.stopMonitoring()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clip")
            img?.isTemplate = true
            button.image = img
            button.action = #selector(toggleWindow)
            button.target = self
        }
    }

    @objc func toggleWindow() {
        if let p = panel, p.isVisible {
            hideWindow()
            return
        }

        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.main?.visibleFrame ?? .zero

        let contentView = ClipPopoverContent(onSelect: { [weak self] text in
            self?.hideWindow()
            if let app = self?.previouslyActiveApp {
                app.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    ClipboardManager.shared.copyToClipboard(text)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let src = CGEventSource(stateID: .hidSystemState)
                        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
                        keyDown?.flags = .maskCommand
                        keyDown?.post(tap: .cghidEventTap)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                            keyUp?.flags = .maskCommand
                            keyUp?.post(tap: .cghidEventTap)
                        }
                    }
                }
            } else {
                ClipboardManager.shared.copyToClipboard(text)
            }
        }, onDismiss: { [weak self] in
            self?.hideWindow()
        })

        let hosting = NSHostingView(rootView: contentView)

        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 520

        var x = mouse.x - panelWidth / 2
        var y = mouse.y - panelHeight - 14

        if x < screen.minX + 10 { x = screen.minX + 10 }
        if x + panelWidth > screen.maxX - 10 { x = screen.maxX - panelWidth - 10 }
        if y < screen.minY + 10 { y = mouse.y + 20 }

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.contentView = hosting
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.animationBehavior = .utilityWindow
        p.minSize = NSSize(width: panelWidth, height: panelHeight)
        p.maxSize = NSSize(width: panelWidth, height: panelHeight)

        panel = p
        p.orderFrontRegardless()
    }

    func hideWindow() {
        panel?.orderOut(nil)
        previouslyActiveApp?.activate(options: .activateIgnoringOtherApps)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "ClipHistory needs Accessibility access to paste text into other apps."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
