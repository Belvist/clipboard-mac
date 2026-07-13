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
    private var notchPanel: NSPanel?
    private var notchHost: NotchHostView?
    private var notchTimer: Timer?
    private var previouslyActiveApp: NSRunningApplication?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UpdateChecker.shared.restoreBackupIfNeeded()
        setupStatusItem()
        setupNotchPanel()
        setupPanel()
        ClipboardManager.shared.startMonitoring()
        HotKeyManager.shared.register()

        NotificationCenter.default.addObserver(self, selector: #selector(toggleWindow), name: .toggleClipWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onClipboardUpdate), name: .clipboardUpdated, object: nil)

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
    }

    private func setupNotchPanel() {
        let host = NotchHostView(rootView: NotchPanelView(count: 0))
        host.onEntered = { [weak self] in self?.notchEntered() }
        host.onExited = { [weak self] in self?.notchExited() }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 38),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.isReleasedWhenClosed = false
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        host.wantsLayer = true
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 38)
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        notchPanel = p
        notchHost = host

        let ta = NSTrackingArea(
            rect: host.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: host, userInfo: nil
        )
        host.addTrackingArea(ta)
    }

    private func notchGeometry(for screen: NSScreen) -> (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat) {
        let sf = screen.frame
        let vf = screen.visibleFrame
        let menuBarH = sf.maxY - vf.maxY
        let screenW = sf.width

        let hasNotch = menuBarH > 30
        let notchW: CGFloat = hasNotch ? screenW * 0.11 : 0
        let contentMargin: CGFloat = 55
        let pillW = hasNotch ? max(240, notchW + contentMargin * 2) : 200
        let pillH = max(menuBarH, 28)
        let pillX = sf.midX - pillW / 2
        let pillY = sf.maxY - pillH
        let notchX = sf.midX - notchW / 2
        return (notchX, notchW, pillX, pillW, pillH, pillY)
    }

    private func positionNotchPanel() {
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)
        p.setFrame(NSRect(x: g.pillX, y: g.pillY, width: g.pillW, height: g.pillH), display: true)
        notchHost?.frame = NSRect(x: 0, y: 0, width: g.pillW, height: g.pillH)
    }

    @objc private func onClipboardUpdate() {
        let count = ClipboardManager.shared.items.count

        guard panel?.isVisible != true else { return }

        notchHost?.rootView = NotchPanelView(count: count)

        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)

        let spring = CAMediaTimingFunction(controlPoints: 0.34, 1.45, 0.64, 1)

        let notchRect = NSRect(x: g.notchX, y: g.pillY, width: g.notchW, height: g.pillH)
        let pillRect = NSRect(x: g.pillX, y: g.pillY, width: g.pillW, height: g.pillH)

        p.setFrame(notchRect, display: false)
        notchHost?.frame = NSRect(x: 0, y: 0, width: g.notchW, height: g.pillH)
        notchHost?.layer?.transform = CATransform3DMakeScale(0.6, 0.6, 1)
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = spring
            ctx.allowsImplicitAnimation = true
            p.animator().setFrame(pillRect, display: true)
            p.animator().alphaValue = 1
        }

        if let layer = notchHost?.layer {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.6
            scale.toValue = 1.0
            scale.duration = 0.5
            scale.timingFunction = spring
            layer.add(scale, forKey: "scaleIn")
            layer.transform = CATransform3DIdentity
        }

        scheduleHide()
    }

    private func collapseNotch() {
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        guard p.alphaValue > 0 else { return }
        let g = notchGeometry(for: screen)

        let spring = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
        let notchRect = NSRect(x: g.notchX, y: g.pillY, width: g.notchW, height: g.pillH)

        if let layer = notchHost?.layer {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 0.6
            scale.duration = 0.3
            scale.timingFunction = spring
            scale.fillMode = .forwards
            scale.isRemovedOnCompletion = false
            layer.add(scale, forKey: "scaleOut")
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = spring
            p.animator().setFrame(notchRect, display: true)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            p.alphaValue = 0
            self?.notchHost?.layer?.removeAllAnimations()
            self?.notchHost?.layer?.transform = CATransform3DIdentity
            self?.notchHost?.frame = NSRect(x: 0, y: 0, width: g.notchW, height: g.pillH)
        })
    }

    private func scheduleHide() {
        notchTimer?.invalidate()
        notchTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.collapseNotch()
        }
    }

    @objc private func notchEntered() {
        guard panel?.isVisible != true else { return }
        notchTimer?.invalidate()

        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)

        if p.alphaValue < 1 {
            let spring = CAMediaTimingFunction(controlPoints: 0.34, 1.45, 0.64, 1)
            let pillRect = NSRect(x: g.pillX, y: g.pillY, width: g.pillW, height: g.pillH)

            if p.alphaValue == 0 {
                p.setFrame(NSRect(x: g.notchX, y: g.pillY, width: g.notchW, height: g.pillH), display: false)
                notchHost?.frame = NSRect(x: 0, y: 0, width: g.notchW, height: g.pillH)
                notchHost?.layer?.transform = CATransform3DMakeScale(0.6, 0.6, 1)
            }

            p.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = spring
                ctx.allowsImplicitAnimation = true
                p.animator().setFrame(pillRect, display: true)
                p.animator().alphaValue = 1
            }

            if let layer = notchHost?.layer {
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 0.6
                scale.toValue = 1.0
                scale.duration = 0.45
                scale.timingFunction = spring
                layer.add(scale, forKey: "scaleHover")
                layer.transform = CATransform3DIdentity
            }
        }
    }

    @objc private func notchExited() {
        scheduleHide()
    }

    @objc private func notchClicked() {
        notchTimer?.invalidate()
        collapseNotch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.toggleWindow()
        }
    }

    private func setupPanel() {
        let contentView = ClipPopoverContent(onSelect: { [weak self] item in
            self?.hidePanel()

            ClipboardManager.shared.copyToClipboard(item)

            guard let app = self?.previouslyActiveApp else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                app.activate(options: .activateIgnoringOtherApps)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
                    keyDown?.flags = .maskCommand
                    keyDown?.post(tap: .cghidEventTap)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                        keyUp?.flags = .maskCommand
                        keyUp?.post(tap: .cghidEventTap)
                    }
                }
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
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Notch Panel (Dynamic Island style)

class NotchHostView: NSHostingView<NotchPanelView> {
    var onEntered: (() -> Void)?
    var onExited: (() -> Void)?

    override func mouseEntered(with event: NSEvent) { onEntered?() }
    override func mouseExited(with event: NSEvent) { onExited?() }
}

struct NotchShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                      control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                      control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchPanelView: View {
    var count: Int = 0

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.leading, 16)
                Spacer()
            }

            HStack {
                Spacer()
                if count > 0 {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            .frame(width: 18, height: 18)
                        Text("\(count)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.trailing, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchShape(cornerRadius: 14).fill(Color.black))
        .clipShape(NotchShape(cornerRadius: 14))
    }
}
