import AppKit
import Foundation
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var clockTimer: Timer?
    private var chimeTimer: Timer?
    private var activeSound: NSSound?

    // Hour Progress HUD state
    private var hudWindow: NSWindow?
    private var hudTimer: Timer?
    private var hudProgressLayer: CAShapeLayer?
    private var hudTextLayer: CATextLayer?

    private let soundKey = "selectedSound"
    private let volumeKey = "selectedVolume"
    private let visualRingKey = "visualRingEnabled"
    private let timeOverlayKey = "timeOverlayEnabled"
    private let hourProgressKey = "hourProgressEnabled"
    private let hudPlacementKey = "hudPlacement"

    private let availableSounds = ["Tink", "Ping", "Pop", "Glass", "Purr"]

    private enum HUDPlacement: String, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var displayName: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            }
        }
    }

    private var hudPlacement: HUDPlacement {
        HUDPlacement(rawValue: UserDefaults.standard.string(forKey: hudPlacementKey) ?? "") ?? .bottomRight
    }

    private lazy var clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private let volumeLevels: [(label: String, value: Float)] = [
        ("Quiet", 0.3),
        ("Medium", 0.6),
        ("Loud", 1.0)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.target = self

        let defaults = UserDefaults.standard
        if defaults.string(forKey: soundKey) == nil {
            defaults.set("Tink", forKey: soundKey)
        }
        if defaults.object(forKey: volumeKey) == nil {
            defaults.set(Float(0.3), forKey: volumeKey)
        }
        if defaults.object(forKey: visualRingKey) == nil {
            defaults.set(true, forKey: visualRingKey)
        }
        if defaults.object(forKey: timeOverlayKey) == nil {
            defaults.set(true, forKey: timeOverlayKey)
        }
        if defaults.object(forKey: hourProgressKey) == nil {
            defaults.set(false, forKey: hourProgressKey)
        }
        if defaults.string(forKey: hudPlacementKey) == nil {
            defaults.set(HUDPlacement.bottomRight.rawValue, forKey: hudPlacementKey)
        }

        updateClock()
        startClockTimer()
        scheduleNextChime()

        if defaults.bool(forKey: hourProgressKey) {
            startHourProgressHUD()
        }
    }

    // MARK: - Clock

    private func updateClock() {
        let timeString = "🕙 \(clockFormatter.string(from: Date()))"
        statusItem.button?.title = timeString
    }

    private func startClockTimer() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
        clockTimer?.tolerance = 5
    }

    // MARK: - Chime

    private func scheduleNextChime() {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        components.hour = (components.hour ?? 0) + 1
        components.minute = 0
        components.second = 0

        guard let nextHour = calendar.date(from: components) else { return }
        let interval = nextHour.timeIntervalSince(now)

        chimeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.handleChimeFire()
        }
        chimeTimer?.tolerance = 2
    }

    private func handleChimeFire() {
        let minute = Calendar.current.component(.minute, from: Date())
        if minute == 0 {
            playChime()
        }
        scheduleNextChime()
    }

    private func playSound() {
        let soundName = UserDefaults.standard.string(forKey: soundKey) ?? "Tink"
        let volume = UserDefaults.standard.float(forKey: volumeKey)
        guard let sound = NSSound(named: NSSound.Name(soundName)) else { return }
        sound.volume = volume
        activeSound = sound   // retain strongly so ARC doesn't release mid-playback
        sound.play()
    }

    private func playChime() {
        playSound()
        triggerVisualAlerts()
    }

    private func triggerVisualAlerts() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: visualRingKey) {
            showScreenRingFlash()
        }
        if defaults.bool(forKey: timeOverlayKey) {
            showTimeOverlay()
        }
        if defaults.bool(forKey: hourProgressKey) {
            pulseHourProgressHUD()
        }
    }

    // MARK: - Feature 1: Screen Ring Flash

    private func showScreenRingFlash() {
        for screen in NSScreen.screens {
            showRingOnScreen(screen)
        }
    }

    private func showRingOnScreen(_ screen: NSScreen) {
        let sf = screen.frame
        let borderWidth: CGFloat = 50

        let window = NSWindow(
            contentRect: sf,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // ARC (not AppKit) owns this window's lifetime; without this, close()
        // triggers an extra AppKit-side release and over-releases the window.
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: CGRect(origin: .zero, size: sf.size))
        contentView.wantsLayer = true
        window.contentView = contentView

        let cyanOpaque = NSColor(red: 0.0, green: 0.831, blue: 1.0, alpha: 0.60).cgColor
        let cyanClear  = NSColor(red: 0.0, green: 0.831, blue: 1.0, alpha: 0.0).cgColor

        // Container layer so a single opacity animation drives all four strips
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: sf.size)

        func addStrip(frame: CGRect, startPt: CGPoint, endPt: CGPoint) {
            let grad = CAGradientLayer()
            grad.frame = frame
            grad.colors = [cyanOpaque, cyanClear]
            grad.startPoint = startPt
            grad.endPoint   = endPt
            container.addSublayer(grad)
        }

        // macOS CALayer origin is bottom-left (Y-up), so:
        // "top" strip lives at y = sf.height - borderWidth
        // "bottom" strip lives at y = 0
        addStrip(
            frame:   CGRect(x: 0, y: sf.height - borderWidth, width: sf.width, height: borderWidth),
            startPt: CGPoint(x: 0.5, y: 1), endPt: CGPoint(x: 0.5, y: 0)   // opaque top → transparent bottom
        )
        addStrip(
            frame:   CGRect(x: 0, y: 0, width: sf.width, height: borderWidth),
            startPt: CGPoint(x: 0.5, y: 0), endPt: CGPoint(x: 0.5, y: 1)   // opaque bottom → transparent top
        )
        addStrip(
            frame:   CGRect(x: 0, y: 0, width: borderWidth, height: sf.height),
            startPt: CGPoint(x: 0, y: 0.5), endPt: CGPoint(x: 1, y: 0.5)   // opaque left → transparent right
        )
        addStrip(
            frame:   CGRect(x: sf.width - borderWidth, y: 0, width: borderWidth, height: sf.height),
            startPt: CGPoint(x: 1, y: 0.5), endPt: CGPoint(x: 0, y: 0.5)   // opaque right → transparent left
        )

        // Start invisible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.opacity = 0
        CATransaction.commit()

        contentView.layer?.addSublayer(container)
        window.orderFrontRegardless()

        // Fade in over 0.3s
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        container.opacity = 1
        CATransaction.commit()

        // Fade out starting at 1.5s, close when done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [window, container] in
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.5)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            CATransaction.setCompletionBlock { [window] in
                window.close()
            }
            container.opacity = 0
            CATransaction.commit()
        }
    }

    // MARK: - Feature 2: Top-Right Time Overlay

    private func showTimeOverlay() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.frame
        let fontSize = min(sf.height * 0.07, 120.0)

        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        let timeString = tf.string(from: Date())

        let panelWidth: CGFloat = max(240, fontSize * 4.5)
        let panelHeight: CGFloat = fontSize + 40
        let inset: CGFloat = 20

        let finalX = sf.maxX - panelWidth - inset
        let finalY = sf.maxY - panelHeight - inset

        let window = NSWindow(
            contentRect: NSRect(x: finalX, y: finalY, width: panelWidth, height: panelHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // ARC (not AppKit) owns this window's lifetime; without this, close()
        // triggers an extra AppKit-side release and over-releases the window.
        window.isReleasedWhenClosed = false

        let bgView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)))
        bgView.wantsLayer = true
        bgView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        bgView.layer?.cornerRadius = 12
        window.contentView = bgView

        let labelFrame = NSRect(x: 12, y: 8, width: panelWidth - 24, height: panelHeight - 16)
        let label = NSTextField(frame: labelFrame)
        label.stringValue = timeString
        label.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.alignment = .center
        label.cell?.wraps = false
        label.cell?.isScrollable = false

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 6
        label.shadow = shadow
        bgView.addSubview(label)

        // Start transparent
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bgView.layer?.opacity = 0
        CATransaction.commit()

        window.orderFrontRegardless()

        // Fade in over 0.4s
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        bgView.layer?.opacity = 1
        CATransaction.commit()

        // Hold 3s then fade out and close
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { [window, bgView] in
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            CATransaction.setCompletionBlock { [window] in
                window.close()
            }
            bgView.layer?.opacity = 0
            CATransaction.commit()
        }
    }

    // MARK: - Feature 3: Hour Progress Arc HUD

    private func startHourProgressHUD() {
        stopHourProgressHUD()
        createHUDWindow()
        updateHUDContent()
        hudTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateHUDContent()
        }
        hudTimer?.tolerance = 5
    }

    private func stopHourProgressHUD() {
        hudTimer?.invalidate()
        hudTimer = nil
        hudWindow?.close()
        hudWindow = nil
        hudProgressLayer = nil
        hudTextLayer = nil
    }

    private func createHUDWindow() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let size: CGFloat = 64
        let inset: CGFloat = 20

        let originX: CGFloat
        let originY: CGFloat
        switch hudPlacement {
        case .topLeft:
            originX = visibleFrame.minX + inset
            originY = visibleFrame.maxY - size - inset
        case .topRight:
            originX = visibleFrame.maxX - size - inset
            originY = visibleFrame.maxY - size - inset
        case .bottomLeft:
            originX = visibleFrame.minX + inset
            originY = visibleFrame.minY + inset
        case .bottomRight:
            originX = visibleFrame.maxX - size - inset
            originY = visibleFrame.minY + inset
        }

        let hudFrame = NSRect(x: originX, y: originY, width: size, height: size)

        let window = NSWindow(
            contentRect: hudFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        // ARC (not AppKit) owns this window's lifetime; without this, close()
        // triggers an extra AppKit-side release and over-releases the window.
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: CGSize(width: size, height: size)))
        contentView.wantsLayer = true
        window.contentView = contentView

        let center = CGPoint(x: size / 2, y: size / 2)
        let outerRadius: CGFloat = 30
        let arcRadius: CGFloat = outerRadius - 5

        // Dark background circle
        let bgLayer = CAShapeLayer()
        bgLayer.path = CGPath(
            ellipseIn: CGRect(
                x: center.x - outerRadius, y: center.y - outerRadius,
                width: outerRadius * 2, height: outerRadius * 2
            ),
            transform: nil
        )
        bgLayer.fillColor = NSColor.black.withAlphaComponent(0.55).cgColor
        bgLayer.strokeColor = nil
        contentView.layer?.addSublayer(bgLayer)

        // Clockwise arc path starting from 12 o'clock (π/2 in Y-up coords)
        let arcPath = CGMutablePath()
        arcPath.addArc(
            center: center,
            radius: arcRadius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - 2 * .pi,
            clockwise: true
        )

        // Dim track ring (full circle)
        let trackLayer = CAShapeLayer()
        trackLayer.path = arcPath
        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
        trackLayer.lineWidth = 5
        trackLayer.lineCap = .round
        contentView.layer?.addSublayer(trackLayer)

        // Orange progress arc
        let progressLayer = CAShapeLayer()
        progressLayer.path = arcPath
        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.strokeColor = NSColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0).cgColor
        progressLayer.lineWidth = 5
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
        contentView.layer?.addSublayer(progressLayer)
        hudProgressLayer = progressLayer

        // Remaining-minutes label
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(x: 0, y: center.y - 9, width: size, height: 18)
        textLayer.alignmentMode = .center
        textLayer.fontSize = 12
        textLayer.font = NSFont.boldSystemFont(ofSize: 12)
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.contentsScale = screen.backingScaleFactor
        textLayer.string = "0m"
        contentView.layer?.addSublayer(textLayer)
        hudTextLayer = textLayer

        window.orderFrontRegardless()
        hudWindow = window
    }

    private func updateHUDContent() {
        let minute = Calendar.current.component(.minute, from: Date())
        let progress = CGFloat(minute) / 60.0
        let remaining = 60 - minute
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.hudProgressLayer?.strokeEnd = progress
            self.hudTextLayer?.string = "\(remaining)m"
            CATransaction.commit()
        }
    }

    private func pulseHourProgressHUD() {
        guard let progressLayer = hudProgressLayer else { return }
        let orange = NSColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0).cgColor
        let yellow = NSColor.yellow.cgColor
        let anim = CABasicAnimation(keyPath: "strokeColor")
        anim.fromValue = orange
        anim.toValue = yellow
        anim.duration = 0.5
        anim.autoreverses = true
        anim.repeatCount = 1
        progressLayer.add(anim, forKey: "pulse")
    }

    // MARK: - Menu

    @objc private func handleStatusItemClick() {
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Sound picker
        let soundMenu = NSMenu()
        let selectedSound = UserDefaults.standard.string(forKey: soundKey) ?? "Tink"
        for name in availableSounds {
            let item = NSMenuItem(title: name, action: #selector(handleSoundSelection(_:)), keyEquivalent: "")
            item.representedObject = name
            item.target = self
            item.state = name == selectedSound ? .on : .off
            soundMenu.addItem(item)
        }
        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        // Volume picker
        let volumeMenu = NSMenu()
        let currentVolume = UserDefaults.standard.float(forKey: volumeKey)
        for level in volumeLevels {
            let item = NSMenuItem(title: level.label, action: #selector(handleVolumeSelection(_:)), keyEquivalent: "")
            item.representedObject = level.value
            item.target = self
            item.state = abs(level.value - currentVolume) < 0.01 ? .on : .off
            volumeMenu.addItem(item)
        }
        let volumeItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeItem.submenu = volumeMenu
        menu.addItem(volumeItem)

        menu.addItem(NSMenuItem.separator())

        // Visual Alerts submenu
        let visualMenu = NSMenu()

        let ringItem = NSMenuItem(title: "Screen Ring Flash", action: #selector(handleToggleVisualRing), keyEquivalent: "")
        ringItem.target = self
        ringItem.state = UserDefaults.standard.bool(forKey: visualRingKey) ? .on : .off
        visualMenu.addItem(ringItem)

        let timeOverlayItem = NSMenuItem(title: "Time Display", action: #selector(handleToggleTimeOverlay), keyEquivalent: "")
        timeOverlayItem.target = self
        timeOverlayItem.state = UserDefaults.standard.bool(forKey: timeOverlayKey) ? .on : .off
        visualMenu.addItem(timeOverlayItem)

        let hudItem = NSMenuItem(title: "Hour Progress HUD", action: #selector(handleToggleHourProgress), keyEquivalent: "")
        hudItem.target = self
        hudItem.state = UserDefaults.standard.bool(forKey: hourProgressKey) ? .on : .off
        visualMenu.addItem(hudItem)

        // HUD Placement submenu
        let placementMenu = NSMenu()
        let currentPlacement = hudPlacement
        for placement in HUDPlacement.allCases {
            let item = NSMenuItem(title: placement.displayName, action: #selector(handleHUDPlacementSelection(_:)), keyEquivalent: "")
            item.representedObject = placement.rawValue
            item.target = self
            item.state = placement == currentPlacement ? .on : .off
            placementMenu.addItem(item)
        }
        let placementItem = NSMenuItem(title: "HUD Placement", action: nil, keyEquivalent: "")
        placementItem.submenu = placementMenu
        visualMenu.addItem(placementItem)

        let visualAlertsItem = NSMenuItem(title: "Visual Alerts", action: nil, keyEquivalent: "")
        visualAlertsItem.submenu = visualMenu
        menu.addItem(visualAlertsItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(handleToggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Preview Alerts
        let previewItem = NSMenuItem(title: "Preview Alerts", action: #selector(handlePreviewAlerts), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit HourlyChime", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc private func handleSoundSelection(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        UserDefaults.standard.set(name, forKey: soundKey)
        playChime()
    }

    @objc private func handleVolumeSelection(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Float else { return }
        UserDefaults.standard.set(value, forKey: volumeKey)
    }

    @objc private func handleToggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSLog("HourlyChime: Launch at login toggle failed: \(error)")
            }
        }
    }

    @objc private func handleToggleVisualRing() {
        let current = UserDefaults.standard.bool(forKey: visualRingKey)
        UserDefaults.standard.set(!current, forKey: visualRingKey)
    }

    @objc private func handleToggleTimeOverlay() {
        let current = UserDefaults.standard.bool(forKey: timeOverlayKey)
        UserDefaults.standard.set(!current, forKey: timeOverlayKey)
    }

    @objc private func handleToggleHourProgress() {
        let current = UserDefaults.standard.bool(forKey: hourProgressKey)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: hourProgressKey)
        if newValue {
            startHourProgressHUD()
        } else {
            stopHourProgressHUD()
        }
    }

    @objc private func handleHUDPlacementSelection(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              rawValue != hudPlacement.rawValue else { return }
        UserDefaults.standard.set(rawValue, forKey: hudPlacementKey)
        if UserDefaults.standard.bool(forKey: hourProgressKey) {
            startHourProgressHUD()   // recreate the HUD window at its new position
        }
    }

    @objc private func handlePreviewAlerts() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.playSound()
            self?.triggerVisualAlerts()
        }
    }

    // MARK: - Helpers

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
