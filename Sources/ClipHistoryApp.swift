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

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var previouslyActiveApp: NSRunningApplication?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UpdateChecker.shared.restoreBackupIfNeeded()
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
        removeMonitors()
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
        updateStatusCount()
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusCount), name: .clipboardUpdated, object: nil)
    }

    @objc private func updateStatusCount() {
        guard let button = statusItem?.button else { return }
        let count = ClipboardManager.shared.items.count
        if count > 0 {
            button.title = "  \(count)"
        } else {
            button.title = ""
        }
    }

    private func setupPanel() {
        let contentView = ClipPopoverContent(onSelect: { [weak self] item in
            self?.hidePanel()
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
            self?.hidePanel()
        })

        let hosting = NSHostingController(rootView: contentView.environmentObject(L10n.shared))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentViewController = hosting
        p.delegate = self
        panel = p
    }

    @objc func toggleWindow() {
        guard let p = panel else { return }
        if p.isVisible {
            hidePanel()
        } else {
            previouslyActiveApp = NSWorkspace.shared.frontmostApplication
            showPanel()
        }
    }

    private func showPanel() {
        guard let p = panel else { return }

        let cursor = NSEvent.mouseLocation
        let screenW = NSScreen.main?.frame.width ?? 800
        let panelW: CGFloat = 400
        let panelH: CGFloat = 520

        var x = cursor.x - panelW / 2
        var y = cursor.y - panelH - 10

        if x < 8 { x = 8 }
        if x + panelW > screenW - 8 { x = screenW - panelW - 8 }
        if y < 8 { y = cursor.y + 20 }

        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.orderFront(nil)

        installMonitors()
        UpdateChecker.shared.checkForUpdates()
    }

    func hidePanel() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let p = self.panel else { return }
            let loc = NSEvent.mouseLocation
            if !p.frame.contains(loc) {
                DispatchQueue.main.async { self.hidePanel() }
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.hidePanel() }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    func showAccessibilityAlert() {
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
