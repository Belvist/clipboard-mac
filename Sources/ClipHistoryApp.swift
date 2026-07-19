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
    private var musicPanel: NSPanel?
    private var musicPanelMonitor: Any?
    private var notchTimer: Timer?

    private var notchExpanded = false

    enum NotchUIState: Equatable {
        case hidden
        case clipboardPill
        case clipboardWave
        case musicPill
        case musicExpanded
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
        let host = NotchHostView(rootView: NotchPanelView(count: 0))
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

    private func stateDidChange(from oldState: NotchUIState) {
        switch (oldState, state) {
        case (_, .hidden):
            collapseNotchVisual()
        case (.hidden, .clipboardPill), (.hidden, .clipboardWave):
            showNotch(animated: true)
        case (.hidden, .musicPill):
            showMusicPill()
        case (_, .musicPill):
            hideMusicPanel()
            showMusicPill()
        case (_, .musicExpanded):
            showMusicPanel()
        case (.clipboardWave, .clipboardPill):
            updatePillView(clipboardWave: false)
        default:
            break
        }
        scheduleHideIfNeeded()
    }

    private func showNotch(animated: Bool) {
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)
        notchHost?.layer?.removeAllAnimations()
        if animated {
            animateNotchIn(g: g)
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
    }

    private func showMusicPill() {
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)
        notchHost?.rootView = NotchPanelView(count: ClipboardManager.shared.items.count)
        notchHost?.layer?.removeAllAnimations()
        positionNotchPanel()
        if !notchExpanded {
            animateNotchExpand(g: g)
            notchExpanded = true
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
    }

    private func updatePillView(clipboardWave: Bool) {
        notchHost?.rootView = NotchPanelView(count: ClipboardManager.shared.items.count, clipboardWave: clipboardWave)
    }

    private func animateNotchIn(g: (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat)) {
        guard let hostLayer = notchHost?.layer else { return }
        let maskLayer = CAShapeLayer()
        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)
        maskLayer.path = collapsed
        hostLayer.mask = maskLayer
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
    }

    private func animateNotchExpand(g: (notchX: CGFloat, notchW: CGFloat, pillX: CGFloat, pillW: CGFloat, pillH: CGFloat, pillY: CGFloat)) {
        guard let hostLayer = notchHost?.layer else { return }
        let maskLayer = CAShapeLayer()
        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)
        maskLayer.path = collapsed
        hostLayer.mask = maskLayer
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.34, 1.45, 0.64, 1))
        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = collapsed
        pathAnim.toValue = expanded
        maskLayer.add(pathAnim, forKey: "expandMusic")
        maskLayer.path = expanded
        CATransaction.commit()
    }

    private func scheduleHideIfNeeded() {
        switch state {
        case .hidden, .musicExpanded, .clipboardPill:
            break
        case .clipboardWave:
            scheduleHide(delay: 4.0)
        case .musicPill:
            if !MediaRemoteHelper.shared.isPlaying {
                scheduleHide(delay: 4.0)
            }
        }
    }

    @objc private func onClipboardUpdate() {
        guard panel?.isVisible != true else { return }
        guard state != .musicExpanded, state != .musicPill else { return }

        if state == .hidden || state == .clipboardPill {
            updatePillView(clipboardWave: true)
            positionNotchPanel()
            state = .clipboardWave
        }
        clipboardWaveTimer?.invalidate()
        clipboardWaveTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.updatePillView(clipboardWave: false)
            if self?.state == .clipboardWave { self?.state = .clipboardPill }
        }
    }

    @objc private func onMusicChanged() {
        let music = MediaRemoteHelper.shared

        if music.isPlaying {
            state = .musicPill
        } else if state == .musicExpanded {
            state = .hidden
        } else if state == .musicPill {
            state = .hidden
        }
    }

    private func collapseNotchVisual() {
        notchExpanded = false
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)

        let hostLayer = notchHost?.layer
        let maskLayer = hostLayer?.mask as? CAShapeLayer

        let collapsed = notchCollapsedPath(g: g)
        let expanded = notchExpandedPath(g: g)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self, self.state == .hidden else { return }
            hostLayer?.opacity = 0
            p.alphaValue = 0
            hostLayer?.mask = nil
            hostLayer?.removeAllAnimations()
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
        guard state != .hidden, state != .musicExpanded else { return }
        notchTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.state = .hidden
        }
    }

    private func startHoverMonitor() {
        hoverMonitor?.invalidate()
        hoverInside = false
        hoverMonitor = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkHover()
        }
    }

    private func checkHover() {
        guard let screen = NSScreen.main else { return }
        guard state != .musicExpanded else {
            hoverInside = false
            return
        }

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

        guard !notchExpanded else { return }
        expandNotchMask()
    }

    private func hoverExited() {
        if state != .hidden && state != .musicExpanded {
            scheduleHide()
        }
    }

    private func expandNotchMask() {
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

    @objc private func notchClicked() {
        notchTimer?.invalidate()
        switch state {
        case .musicPill:
            state = .musicExpanded
        case .musicExpanded:
            state = .musicPill
        case .clipboardPill, .clipboardWave:
            state = .hidden
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.toggleWindow()
            }
        case .hidden:
            toggleWindow()
        }
    }

    private func hideMusicPanel() {
        musicPanel?.orderOut(nil)
        musicPanelMonitor.map { NSEvent.removeMonitor($0) }
        musicPanelMonitor = nil
        guard let screen = NSScreen.main, let p = notchPanel else { return }
        let g = notchGeometry(for: screen)
        notchHost?.rootView = NotchPanelView(count: ClipboardManager.shared.items.count)
        p.setFrame(NSRect(x: g.pillX, y: g.pillY, width: g.pillW, height: g.pillH), display: true)
        notchHost?.frame = NSRect(x: 0, y: 0, width: g.pillW, height: g.pillH)
    }

    private func showMusicPanel() {
        guard let screen = NSScreen.main else { return }
        let g = notchGeometry(for: screen)

        let musicView = ExpandedMusicView(onClose: { [weak self] in
            self?.state = .musicPill
        })
        let hosting = NSHostingController(rootView: musicView)
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 14
        hosting.view.layer?.masksToBounds = true
        hosting.view.layer?.backgroundColor = NSColor.black.cgColor

        if musicPanel == nil {
            let mp = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 140),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            mp.level = .screenSaver
            mp.isOpaque = false
            mp.backgroundColor = .clear
            mp.hidesOnDeactivate = false
            mp.isMovableByWindowBackground = false
            mp.isReleasedWhenClosed = false
            mp.hasShadow = false
            mp.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            mp.contentViewController = hosting
            musicPanel = mp
        } else {
            musicPanel?.contentViewController = hosting
        }

        let panelW: CGFloat = g.pillW
        let panelH: CGFloat = 120
        let panelX = g.pillX
        let panelY = g.pillY - panelH - 4

        musicPanel?.setFrame(NSRect(x: panelX, y: panelY, width: panelW, height: panelH), display: true)
        musicPanel?.alphaValue = 0
        musicPanel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            musicPanel?.animator().alphaValue = 1
        }

        if let m = musicPanelMonitor { NSEvent.removeMonitor(m) }
        musicPanelMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let mp = self.musicPanel, mp.isVisible else { return }
            let loc = NSEvent.mouseLocation
            let notchVisible = self.notchPanel?.frame.contains(loc) ?? false
            let panelVisible = mp.frame.contains(loc)
            if !notchVisible && !panelVisible {
                DispatchQueue.main.async {
                    self.state = .musicPill
                }
            }
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
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onClicked?() }
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

struct ExpandedMusicView: View {
    @ObservedObject private var music = MediaRemoteHelper.shared
    var onClose: (() -> Void)?
    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var displayProgress: Double {
        if isDragging { return dragProgress }
        guard music.duration > 0 else { return 0 }
        return min(music.elapsed / music.duration, 1.0)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let art = music.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(music.title.isEmpty ? "Not Playing" : music.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(music.artist.isEmpty ? "—" : music.artist)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: geo.size.width * displayProgress, height: 3)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            isDragging = true
                            let pct = max(0, min(1, value.location.x / geo.size.width))
                            dragProgress = pct
                        }
                        .onEnded { value in
                            let pct = max(0, min(1, value.location.x / geo.size.width))
                            let target = pct * music.duration
                            music.seekTo(target)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isDragging = false
                            }
                        }
                )
            }
            .frame(height: 20)
            .padding(.top, 8)

            HStack {
                Text(formatTime(music.elapsed))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("-\(formatTime(max(0, music.duration - music.elapsed)))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(spacing: 28) {
                Button(action: { music.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { music.togglePlayPause() }) {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { music.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
