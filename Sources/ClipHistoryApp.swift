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

    private var notchExpanded = false
    private var contentExpanded = false

    enum NotchUIState: Equatable {
        case hidden
        case clipboardPill
        case clipboardWave
        case musicPill
        case clipboardOverMusic
    }

    private var state: NotchUIState = .hidden {
        didSet { stateDidChange(from: oldValue) }
    }

    private var previouslyActiveApp: NSRunningApplication?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var clipboardWaveTimer: Timer?
    private var lastToggleTime: Date?
    private var hoverMonitor: Timer?
    private var hoverInside = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UpdateChecker.shared.restoreBackupIfNeeded()
        setupStatusItem()
        setupNotchPanel()
        setupPanel()
        ClipboardManager.shared.startMonitoring()
        HotKeyManager.shared.register()
        MediaRemoteHelper.shared.startPolling()

        NotificationCenter.default.addObserver(self, selector: #selector(toggleWindow), name: .toggleClipWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onClipboardUpdate), name: .clipboardUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onMusicChanged), name: .musicStateChanged, object: nil)

        startHoverMonitor()

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
        MediaRemoteHelper.shared.stopPolling()
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
        let host = NotchHostView(rootView: NotchPanelView(mode: .clipboard(count: 0, wave: false, preview: "")))
        host.onClicked = { [weak self] in self?.notchClicked() }

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
    }

    private func notchGeometry(for screen: NSScreen) -> (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat) {
        let sf = screen.frame
        let vf = screen.visibleFrame
        let menuBarH = sf.maxY - vf.maxY
        let screenW = sf.width

        let hasNotch = menuBarH > 30
        let notchW: CGFloat = hasNotch ? screenW * 0.11 : 0
        let contentMargin: CGFloat = 55
        var pillW = hasNotch ? max(240, notchW + contentMargin * 2) : 200

        if contentExpanded && (state == .musicPill || state == .clipboardOverMusic) {
            pillW = max(pillW, 380)
        } else if state == .musicPill || state == .clipboardOverMusic {
            pillW = max(pillW, 280)
        }

        let pillH: CGFloat = contentExpanded ? max(menuBarH + 18, 46) : max(menuBarH, 28)
        let pillX = sf.midX - pillW / 2
        let pillY = sf.maxY - pillH
        let notchX = sf.midX - notchW / 2
        return (notchX, notchW, pillX, pillW, pillH, pillY)
    }

    private func modeForState() -> NotchContentMode {
        let count = ClipboardManager.shared.items.count
        let preview = String(ClipboardManager.shared.items.first?.text.prefix(28) ?? "")
        switch state {
        case .hidden, .clipboardPill:
            return .clipboard(count: count, wave: false, preview: preview)
        case .clipboardWave:
            return .clipboard(count: count, wave: true, preview: preview)
        case .musicPill:
            return .music
        case .clipboardOverMusic:
            return .combined(count: count, wave: true, preview: preview)
        }
    }

    private func updateNotchView() {
        notchHost?.rootView = NotchPanelView(mode: modeForState(), expanded: contentExpanded)
    }

    private func notchMaskPath(rect: CGRect, notchW: CGFloat, pillH: CGFloat) -> CGPath {
        let r: CGFloat = 14
        let path = CGMutablePath()
        let top = rect.minY
        let bot = rect.maxY
        let lft = rect.minX
        let rgt = rect.maxX

        path.move(to: CGPoint(x: lft, y: top))
        path.addLine(to: CGPoint(x: rgt, y: top))
        path.addLine(to: CGPoint(x: rgt, y: bot - r))
        path.addQuadCurve(to: CGPoint(x: rgt - r, y: bot), control: CGPoint(x: rgt, y: bot))
        path.addLine(to: CGPoint(x: lft + r, y: bot))
        path.addQuadCurve(to: CGPoint(x: lft, y: bot - r), control: CGPoint(x: lft, y: bot))
        path.closeSubpath()
        return path
    }

    private func notchCollapsedPath(g: (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat)) -> CGPath {
        let centerX = g.pillW / 2
        let w: CGFloat = g.notchW
        let rect = CGRect(x: centerX - w / 2, y: 0, width: w, height: g.pillH)
        return notchMaskPath(rect: rect, notchW: w, pillH: g.pillH)
    }

    private func notchExpandedPath(g: (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat)) -> CGPath {
        let rect = CGRect(x: 0, y: 0, width: g.pillW, height: g.pillH)
        return notchMaskPath(rect: rect, notchW: g.notchW, pillH: g.pillH)
    }

    private func positionNotchPanel() {
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)
        p.setFrame(NSRect(x: g.pillX, y: g.pillY, width: g.pillW, height: g.pillH), display: true)
        notchHost?.frame = NSRect(x: 0, y: 0, width: g.pillW, height: g.pillH)
    }

    private func stateDidChange(from oldState: NotchUIState) {
        debugLog("state: \(oldState) -> \(state)")
        switch (oldState, state) {
        case (_, .hidden):
            debugLog("case: (_, .hidden)")
            contentExpanded = false
            collapseNotchVisual()
        case (.hidden, .clipboardPill), (.hidden, .clipboardWave):
            debugLog("case: clipboard show")
            updateNotchView()
            showNotch(animated: true)
        case (.clipboardPill, .clipboardWave), (.clipboardWave, .clipboardPill):
            debugLog("case: clipboard toggle wave")
            updateNotchView()
        case (_, .clipboardOverMusic):
            debugLog("case: clipboardOverMusic")
            updateNotchView()
            showNotch(animated: true)
        case (.hidden, .musicPill):
            debugLog("case: (.hidden, .musicPill)")
            showMusicPill()
        case (_, .musicPill):
            debugLog("case: (_, .musicPill)")
            showMusicPill()
        default:
            debugLog("case: DEFAULT")
            break
        }
        scheduleHideIfNeeded()
    }

    private func showNotch(animated: Bool) {
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)
        notchHost?.layer?.removeAllAnimations()
        notchHost?.layer?.opacity = 1
        notchHost?.layer?.mask = nil
        positionNotchPanel()
        if animated {
            animateNotchIn(g: g)
        } else {
            notchExpanded = true
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
    }

    private func showMusicPill() {
        guard let screen = NSScreen.main, let p = notchPanel else {
            debugLog("showMusicPill: ABORT screen=\(NSScreen.main != nil) panel=\(notchPanel != nil)")
            return
        }
        let g = notchGeometry(for: screen)
        debugLog("showMusicPill: pillX=\(g.pillX) pillY=\(g.pillY) pillW=\(g.pillW) pillH=\(g.pillH)")
        updateNotchView()
        notchHost?.layer?.removeAllAnimations()
        notchHost?.layer?.opacity = 1
        notchHost?.layer?.mask = nil
        positionNotchPanel()
        animateNotchExpand(g: g)
        notchExpanded = true
        p.alphaValue = 1
        p.orderFrontRegardless()
        debugLog("showMusicPill DONE: panel frame=\(p.frame) alpha=\(p.alphaValue) visible=\(p.isVisible)")
    }

    private func animateNotchIn(g: (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat)) {
        guard let hostLayer = notchHost?.layer else { return }
        hostLayer.mask = nil
        let maskLayer = CAShapeLayer()
        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)
        maskLayer.path = collapsed
        hostLayer.mask = maskLayer
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = collapsed
        pathAnim.toValue = expanded
        maskLayer.add(pathAnim, forKey: "expand")
        maskLayer.path = expanded
        CATransaction.commit()
        notchExpanded = true
    }

    private func animateNotchExpand(g: (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat)) {
        guard let hostLayer = notchHost?.layer else { return }
        hostLayer.mask = nil
        let maskLayer = CAShapeLayer()
        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)
        maskLayer.path = collapsed
        hostLayer.mask = maskLayer
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = collapsed
        pathAnim.toValue = expanded
        maskLayer.add(pathAnim, forKey: "expandMusic")
        maskLayer.path = expanded
        CATransaction.commit()
    }

    private func scheduleHideIfNeeded() {
        switch state {
        case .hidden:
            break
        case .clipboardWave, .clipboardOverMusic:
            break
        case .clipboardPill:
            scheduleHide(delay: 6.0)
        case .musicPill:
            if !MediaRemoteHelper.shared.isPlaying {
                debugLog("scheduleHideIfNeeded: scheduling hide for musicPill (not playing)")
                scheduleHide(delay: 4.0)
            } else {
                debugLog("scheduleHideIfNeeded: musicPill is playing, no hide")
            }
        }
    }

    @objc private func onClipboardUpdate() {
        clipboardWaveTimer?.invalidate()
        if state == .hidden || state == .clipboardPill || state == .clipboardWave {
            state = .clipboardWave
        } else if state == .musicPill || state == .clipboardOverMusic {
            state = .clipboardOverMusic
        }
        clipboardWaveTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .clipboardWave {
                self.updateNotchView()
                self.state = .clipboardPill
            } else if self.state == .clipboardOverMusic {
                self.updateNotchView()
            }
        }
    }

    @objc private func onMusicChanged() {
        let music = MediaRemoteHelper.shared
        debugLog("onMusicChanged: isPlaying=\(music.isPlaying) title=\(music.title)")

        if music.isPlaying {
            if state == .clipboardWave || state == .clipboardOverMusic {
                state = .clipboardOverMusic
            } else {
                state = .musicPill
            }
        } else {
            if state == .musicPill {
                state = .hidden
            }
        }
    }

    private func collapseNotchVisual() {
        debugLog("collapseNotchVisual called")
        notchExpanded = false
        guard let screen = NSScreen.main, let _ = notchPanel else { return }
        let g = notchGeometry(for: screen)

        let hostLayer = notchHost?.layer
        let maskLayer = hostLayer?.mask as? CAShapeLayer

        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else { return }
            self.notchHost?.layer?.mask = nil
            self.notchHost?.layer?.removeAllAnimations()
            self.notchHost?.layer?.opacity = 0
            self.notchPanel?.alphaValue = 0
        }

        if let mask = maskLayer {
            let pathAnim = CABasicAnimation(keyPath: "path")
            pathAnim.fromValue = expanded
            pathAnim.toValue = collapsed
            mask.add(pathAnim, forKey: "collapse")
            mask.path = collapsed
        } else {
            let maskLayer = CAShapeLayer()
            maskLayer.path = collapsed
            hostLayer?.mask = maskLayer
        }

        CATransaction.commit()
    }

    private func scheduleHide(delay: TimeInterval = 10.0) {
        debugLog("scheduleHide: delay=\(delay) state=\(state)")
        notchTimer?.invalidate()
        guard state != .hidden else { return }
        notchTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.state = .hidden
        }
    }

    private func startHoverMonitor() {
        hoverMonitor?.invalidate()
        hoverInside = false
        hoverMonitor = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkHoverIfNeeded()
        }
    }

    private func checkHoverIfNeeded() {
        guard let screen = NSScreen.main else { return }
        let loc = NSEvent.mouseLocation
        let nearTop = loc.y >= screen.frame.maxY - 50
        let active = state != .hidden
        let panelOpen = panel?.isVisible == true
        guard nearTop || active || panelOpen else { return }
        checkHover()
    }

    private func checkHover() {
        guard let screen = NSScreen.main else { return }

        let g = notchGeometry(for: screen)
        let loc = NSEvent.mouseLocation
        let notchRect = NSRect(x: g.pillX, y: g.pillY, width: g.pillW, height: g.pillH)
        let inside = notchRect.contains(loc)

        if inside && !hoverInside {
            hoverInside = true
            hoverEntered()
        } else if !inside && hoverInside {
            hoverInside = false
            hoverExited()
        }
    }

    private func hoverEntered() {
        guard panel?.isVisible != true else { return }
        notchTimer?.invalidate()

        if state == .hidden {
            state = .clipboardPill
            return
        }

        if state == .musicPill || state == .clipboardOverMusic {
            contentExpanded = true
            updateNotchView()
            positionNotchPanel()
            expandNotchMask()
            return
        }

        guard notchPanel?.alphaValue != 1 else { return }
        expandNotchMask()
    }

    private func hoverExited() {
        if contentExpanded {
            contentExpanded = false
            updateNotchView()
            positionNotchPanel()
        }

        if state == .clipboardWave {
            return
        } else if state == .musicPill {
            if !MediaRemoteHelper.shared.isPlaying {
                scheduleHide()
            }
        }
    }

    private func expandNotchMask() {
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)
        let hostLayer = notchHost?.layer
        hostLayer?.removeAllAnimations()
        hostLayer?.opacity = 1
        hostLayer?.mask = nil
        p.alphaValue = 1
        p.orderFrontRegardless()

        let maskLayer = CAShapeLayer()
        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)
        maskLayer.path = collapsed
        hostLayer?.mask = maskLayer

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = collapsed
        pathAnim.toValue = expanded
        maskLayer.add(pathAnim, forKey: "expandHover")
        maskLayer.path = expanded
        CATransaction.commit()

        notchExpanded = true
    }

    @objc private func notchClicked() {
        notchTimer?.invalidate()
        switch state {
        case .clipboardPill, .clipboardWave, .clipboardOverMusic:
            state = .hidden
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.toggleWindow()
            }
        case .musicPill:
            state = .hidden
        case .hidden:
            toggleWindow()
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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.titleVisibility = .hidden
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentViewController = hosting
        p.delegate = self
        panel = p
    }

    @objc func toggleWindow() {
        guard let p = panel else { return }
        let now = Date()
        if let last = lastToggleTime, now.timeIntervalSince(last) < 0.4 { return }
        lastToggleTime = now
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

