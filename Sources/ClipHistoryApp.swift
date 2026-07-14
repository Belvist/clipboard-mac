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
    private var musicActive = false
    private var clipboardWaveActive = false
    private var previouslyActiveApp: NSRunningApplication?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var clipboardWaveTimer: Timer?
    private var lastToggleTime: Date?

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

    @objc private func onClipboardUpdate() {
        let count = ClipboardManager.shared.items.count

        guard panel?.isVisible != true else { return }

        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)

        notchHost?.rootView = NotchPanelView(count: count, clipboardWave: true)
        clipboardWaveActive = true
        clipboardWaveTimer?.invalidate()
        clipboardWaveTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.clipboardWaveActive = false
            self?.notchHost?.rootView = NotchPanelView(count: ClipboardManager.shared.items.count)
        }
        positionNotchPanel()

        let alreadyVisible = p.alphaValue > 0.5

        let hostLayer = notchHost?.layer
        hostLayer?.removeAllAnimations()
        hostLayer?.transform = CATransform3DIdentity
        hostLayer?.opacity = 1

        let maskLayer = CAShapeLayer()
        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)

        if alreadyVisible {
            maskLayer.path = expanded
            hostLayer?.mask = maskLayer
            scheduleHide()
            return
        }

        maskLayer.path = collapsed
        hostLayer?.mask = maskLayer

        p.alphaValue = 1
        p.orderFrontRegardless()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.34, 1.45, 0.64, 0.64))

        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = collapsed
        pathAnim.toValue = expanded
        maskLayer.add(pathAnim, forKey: "expand")
        maskLayer.path = expanded

        CATransaction.commit()

        notchExpanded = true
        scheduleHide()
    }

    @objc private func onMusicChanged() {
        let music = MediaRemoteHelper.shared
        let wasActive = musicActive
        musicActive = music.isPlaying

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let screen = NSScreen.main, let p = self.notchPanel else { return }
            let g = self.notchGeometry(for: screen)

            if music.isPlaying {
                self.notchTimer?.invalidate()
                self.clipboardWaveActive = false
                self.notchHost?.rootView = NotchPanelView(count: ClipboardManager.shared.items.count)
                self.positionNotchPanel()

                let hostLayer = self.notchHost?.layer
                hostLayer?.removeAllAnimations()
                hostLayer?.transform = CATransform3DIdentity
                hostLayer?.opacity = 1

                let collapsed = self.notchCollapsedPath(g: g)
                let expanded = self.notchExpandedPath(g: g)

                if self.notchExpanded {
                    let maskLayer = CAShapeLayer()
                    maskLayer.path = expanded
                    hostLayer?.mask = maskLayer
                    p.alphaValue = 1
                    p.orderFrontRegardless()
                } else {
                    let maskLayer = CAShapeLayer()
                    maskLayer.path = collapsed
                    hostLayer?.mask = maskLayer

                    p.alphaValue = 1
                    p.orderFrontRegardless()

                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.45)
                    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.34, 1.45, 0.64, 1))

                    let pathAnim = CABasicAnimation(keyPath: "path")
                    pathAnim.fromValue = collapsed
                    pathAnim.toValue = expanded
                    maskLayer.add(pathAnim, forKey: "expand")
                    maskLayer.path = expanded

                    CATransaction.commit()
                }

                self.notchExpanded = true
            } else if wasActive {
                self.scheduleHide()
            }
        }
    }

    private func collapseNotch() {
        notchExpanded = false
        clipboardWaveActive = false
        guard !MediaRemoteHelper.shared.isPlaying else { return }
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        guard p.alphaValue > 0.01 else { return }
        let g = notchGeometry(for: screen)

        let hostLayer = notchHost?.layer
        let maskLayer = hostLayer?.mask as? CAShapeLayer

        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1))
        CATransaction.setCompletionBlock {
            p.alphaValue = 0.01
            hostLayer?.mask = nil
            hostLayer?.removeAllAnimations()
            hostLayer?.opacity = 1
        }

        if let mask = maskLayer {
            let pathAnim = CABasicAnimation(keyPath: "path")
            pathAnim.fromValue = expanded
            pathAnim.toValue = collapsed
            mask.add(pathAnim, forKey: "collapse")
            mask.path = collapsed
        }

        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1
        fadeAnim.toValue = 0
        fadeAnim.beginTime = CACurrentMediaTime() + 0.1
        fadeAnim.fillMode = .forwards
        fadeAnim.isRemovedOnCompletion = false
        fadeAnim.duration = 0.2
        hostLayer?.add(fadeAnim, forKey: "fadeOut")

        CATransaction.commit()
    }

    private func scheduleHide(delay: TimeInterval = 10.0) {
        notchTimer?.invalidate()
        guard !MediaRemoteHelper.shared.isPlaying else { return }
        notchTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.collapseNotch()
        }
    }

    @objc private func notchEntered() {
        guard panel?.isVisible != true else { return }
        guard !notchExpanded else { return }
        notchTimer?.invalidate()

        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)

        let hostLayer = notchHost?.layer
        hostLayer?.removeAllAnimations()
        hostLayer?.opacity = 1
        p.alphaValue = 1
        p.orderFrontRegardless()

        let maskLayer = CAShapeLayer()
        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)

        maskLayer.path = collapsed
        hostLayer?.mask = maskLayer

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.34, 1.45, 0.64, 1))

        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = collapsed
        pathAnim.toValue = expanded
        maskLayer.add(pathAnim, forKey: "expandHover")
        maskLayer.path = expanded

        CATransaction.commit()

        notchExpanded = true
    }

    @objc private func notchExited() {
        scheduleHide()
    }

    @objc private func notchClicked() {
        notchTimer?.invalidate()
        collapseNotch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
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

// MARK: - Notch Panel (Dynamic Island style)

class NotchHostView: NSHostingView<NotchPanelView> {
    var onEntered: (() -> Void)?
    var onExited: (() -> Void)?

    override func mouseEntered(with event: NSEvent) { onEntered?() }
    override func mouseExited(with event: NSEvent) { onExited?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
    }
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
    var clipboardWave: Bool = false
    @ObservedObject private var music = MediaRemoteHelper.shared

    var body: some View {
        ZStack {
            HStack {
                if music.hasMusic, let art = music.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 25, height: 22)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .padding(.leading, 10)
                } else {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.leading, 16)
                }
                Spacer()
            }

            HStack {
                Spacer()
                if count > 0, clipboardWave {
                    WaveformBars(isPlaying: true, seed: "\(count)")
                        .padding(.trailing, 10)
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            .frame(width: 18, height: 18)
                        Text("\(count)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.trailing, 14)
                } else if music.isPlaying {
                    WaveformBars(isPlaying: true, seed: music.title)
                        .padding(.trailing, 14)
                } else if count > 0 {
                    WaveformBars(isPlaying: true, seed: "\(count)")
                        .padding(.trailing, 10)
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            .frame(width: 18, height: 18)
                        Text("\(count)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.trailing, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NotchShape(cornerRadius: 14).fill(Color.black))
        .clipShape(NotchShape(cornerRadius: 14))
    }
}
