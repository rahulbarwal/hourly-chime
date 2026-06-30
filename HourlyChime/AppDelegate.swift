import AppKit
import Foundation
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var clockTimer: Timer?
    private var chimeTimer: Timer?

    private let soundKey = "selectedSound"
    private let volumeKey = "selectedVolume"

    private let availableSounds = ["Tink", "Ping", "Pop", "Glass", "Purr"]

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

        if UserDefaults.standard.string(forKey: soundKey) == nil {
            UserDefaults.standard.set("Tink", forKey: soundKey)
        }
        if UserDefaults.standard.object(forKey: volumeKey) == nil {
            UserDefaults.standard.set(Float(0.3), forKey: volumeKey)
        }

        updateClock()
        startClockTimer()
        scheduleNextChime()
    }

    // MARK: - Clock

    private func updateClock() {
        let timeString = "🕙 \(clockFormatter.string(from: Date()))"
        statusItem.button?.title = timeString
    }

    private func startClockTimer() {
        // Fire every 30s so display is never more than 30s stale
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

    private func playChime() {
        let soundName = UserDefaults.standard.string(forKey: soundKey) ?? "Tink"
        let volume = UserDefaults.standard.float(forKey: volumeKey)
        guard let sound = NSSound(named: NSSound.Name(soundName)) else { return }
        sound.volume = volume
        sound.play()
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

        // Launch at login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(handleToggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(loginItem)

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
        // Preview the sound on selection
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

    // MARK: - Helpers

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
