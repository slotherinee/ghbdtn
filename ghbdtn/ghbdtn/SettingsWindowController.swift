import Cocoa
import Carbon

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?

    private var hotkeyTypePopup: NSPopUpButton!
    private var launchAtLoginCheckbox: NSButton!
    private var switchLayoutCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 278),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.title")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildUI()
        applyPersistedSettings()
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        var y: CGFloat = 16

        // Save button (bottom)
        let saveBtn = NSButton(title: L("button.save"), target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 294, y: y, width: 90, height: 28)
        saveBtn.keyEquivalent = "\r"
        cv.addSubview(saveBtn)
        y += 50

        // ── General section — content first, header on top ───────
        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: L("settings.launchAtLogin"),
            target: self, action: #selector(toggleLaunchAtLogin)
        )
        launchAtLoginCheckbox.frame = NSRect(x: 16, y: y, width: 350, height: 20)
        cv.addSubview(launchAtLoginCheckbox)
        y += 28

        switchLayoutCheckbox = NSButton(
            checkboxWithTitle: L("settings.switchLayout"),
            target: self, action: #selector(toggleSwitchLayout)
        )
        switchLayoutCheckbox.frame = NSRect(x: 16, y: y, width: 350, height: 20)
        cv.addSubview(switchLayoutCheckbox)
        y += 34
        addSectionHeader(L("settings.section.general"), to: cv, y: y); y += 28

        // ── Separator ────────────────────────────────────────────
        addSeparator(to: cv, y: y); y += 14

        // ── Hotkey section — content first, header on top ────────
        addLabel(L("settings.hotkey.trigger"), to: cv, frame: NSRect(x: 16, y: y + 3, width: 110, height: 18))
        hotkeyTypePopup = NSPopUpButton(frame: NSRect(x: 134, y: y, width: 250, height: 26))
        hotkeyTypePopup.addItems(withTitles: [
            L("hotkey.doubleControl"),
            L("hotkey.doubleOption"),
            L("hotkey.optionSpace")
        ])
        hotkeyTypePopup.target = self
        hotkeyTypePopup.action = #selector(hotkeyTypeChanged)
        cv.addSubview(hotkeyTypePopup)
        y += 32

        // Hint: "Выдели текст и нажми …"
        let hintLabel = NSTextField(labelWithString: "")
        hintLabel.frame = NSRect(x: 16, y: y, width: 368, height: 16)
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.tag = 77
        cv.addSubview(hintLabel)
        y += 22

        addSectionHeader(L("settings.section.hotkey"), to: cv, y: y)
    }

    @objc private func hotkeyTypeChanged() {
        updateHotkeyHint()
    }

    private func updateHotkeyHint() {
        guard let hintLabel = window?.contentView?.viewWithTag(77) as? NSTextField else { return }
        let idx = hotkeyTypePopup.indexOfSelectedItem
        let combo: String
        switch idx {
        case 1: combo = L("hotkey.doubleOption")
        case 2: combo = "⌥ Space"
        default: combo = L("hotkey.doubleControl")
        }
        hintLabel.stringValue = L("settings.hotkey.hint") + " " + combo
    }

    // MARK: - Helpers

    private func addLabel(_ text: String, to view: NSView, frame: NSRect) {
        let tf = NSTextField(labelWithString: text)
        tf.frame = frame
        tf.font = NSFont.systemFont(ofSize: 13)
        view.addSubview(tf)
    }

    private func addSectionHeader(_ text: String, to view: NSView, y: CGFloat) {
        let tf = NSTextField(labelWithString: text.uppercased())
        tf.frame = NSRect(x: 16, y: y, width: 300, height: 16)
        tf.font = NSFont.boldSystemFont(ofSize: 10)
        tf.textColor = .secondaryLabelColor
        view.addSubview(tf)
    }

    private func addSeparator(to view: NSView, y: CGFloat) {
        let box = NSBox(frame: NSRect(x: 16, y: y, width: 368, height: 1))
        box.boxType = .separator
        view.addSubview(box)
    }

    // MARK: - Persist

    private func applyPersistedSettings() {
        updateLaunchAtLoginCheckbox()
        switchLayoutCheckbox.state = UserDefaults.standard.bool(forKey: "switchLayoutAfterTranslation") ? .on : .off
        let config = HotkeyConfig.load()
        switch config.kind {
        case .doubleTapControl: hotkeyTypePopup.selectItem(at: 0)
        case .doubleTapOption:  hotkeyTypePopup.selectItem(at: 1)
        case .optionSpace:      hotkeyTypePopup.selectItem(at: 2)
        }
        updateHotkeyHint()
    }

    @objc private func toggleSwitchLayout() {
        UserDefaults.standard.set(switchLayoutCheckbox.state == .on, forKey: "switchLayoutAfterTranslation")
    }

    // MARK: - Launch at Login

    private var launchAgentURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/im.alef.ghbdtn.plist")
    }

    private func updateLaunchAtLoginCheckbox() {
        launchAtLoginCheckbox.state =
            FileManager.default.fileExists(atPath: launchAgentURL.path) ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAtLoginCheckbox.state == .on {
            enableLaunchAtLogin()
        } else {
            disableLaunchAtLogin()
        }
    }

    private func enableLaunchAtLogin() {
        guard let execURL = Bundle.main.executableURL else { return }
        let plist: [String: Any] = [
            "Label": "im.alef.ghbdtn",
            "ProgramArguments": [execURL.path],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        do {
            let dir = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
            launchctl("load", launchAgentURL.path)
        } catch {
            launchAtLoginCheckbox.state = .off
        }
    }

    private func disableLaunchAtLogin() {
        launchctl("unload", launchAgentURL.path)
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private func launchctl(_ command: String, _ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = [command, path]
        try? p.run()
    }

    // MARK: - Window delegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - Save

    @objc private func save() {
        let config: HotkeyConfig
        switch hotkeyTypePopup.indexOfSelectedItem {
        case 1:  config = HotkeyConfig(kind: .doubleTapOption)
        case 2:  config = HotkeyConfig(kind: .optionSpace)
        default: config = HotkeyConfig(kind: .doubleTapControl)
        }
        config.save()
        NotificationCenter.default.post(name: .hotkeyConfigChanged, object: nil)
        window?.close()
    }
}
