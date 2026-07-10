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
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
        ClipboardManager.shared.startMonitoring()
        HotKeyManager.shared.register()

        NotificationCenter.default.addObserver(self, selector: #selector(toggleWindow), name: .toggleClipWindow, object: nil)

        if !checkAccessibility() {
            let launchedBefore = UserDefaults.standard.bool(forKey: "hasLaunched")
            if !launchedBefore {
                UserDefaults.standard.set(true, forKey: "hasLaunched")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.showAccessibilityAlert()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
        ClipboardManager.shared.stopMonitoring()
        removeClickMonitor()
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

    private func setupPanel() {
        let contentView = ClipPopoverContent(onSelect: { [weak self] item in
            self?.hideWindow()
            if let app = self?.previouslyActiveApp {
                app.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    ClipboardManager.shared.copyToClipboard(item)
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
                ClipboardManager.shared.copyToClipboard(item)
            }
        }, onDismiss: { [weak self] in
            self?.hideWindow()
        })

        let hosting = NSHostingView(rootView: contentView.environmentObject(L10n.shared))

        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 520

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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

        // Hide traffic light buttons
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true

        panel = p
    }

    private func updatePanelMask() {
        guard let cv = panel?.contentView else { return }
        cv.wantsLayer = true
        let mask = CAShapeLayer()
        mask.path = CGPath(roundedRect: cv.bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
        cv.layer?.mask = mask
    }

    @objc func toggleWindow() {
        if let p = panel, p.isVisible {
            hideWindow()
            return
        }

        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        guard let p = panel else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let panelWidth = p.frame.width
        let panelHeight = p.frame.height

        var x = mouse.x - panelWidth / 2
        var y = mouse.y - panelHeight - 14

        if x < screen.minX + 10 { x = screen.minX + 10 }
        if x + panelWidth > screen.maxX - 10 { x = screen.maxX - panelWidth - 10 }
        if y < screen.minY + 10 { y = mouse.y + 20 }

        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.orderFrontRegardless()
        updatePanelMask()
        setupClickMonitor()
    }

    func hideWindow() {
        panel?.orderOut(nil)
        removeClickMonitor()
        previouslyActiveApp?.activate(options: .activateIgnoringOtherApps)
    }

    private func setupClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else { return }

            // Convert click location to screen coordinates
            let clickLocation = NSEvent.mouseLocation

            // Check if click is inside the panel
            let panelFrame = panel.frame
            if panelFrame.contains(clickLocation) {
                return // Click is inside panel, don't hide
            }

            // Click is outside panel, hide it
            DispatchQueue.main.async {
                self.hideWindow()
            }
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.shared.tr("acc_title")
        alert.informativeText = L10n.shared.tr("acc_msg")
        alert.addButton(withTitle: L10n.shared.tr("acc_open"))
        alert.addButton(withTitle: L10n.shared.tr("acc_later"))
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessibility()
        }
    }
}
