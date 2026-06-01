import Cocoa
import Carbon
import CoreGraphics
import ServiceManagement

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onClose: (() -> Void)?

    private var checkboxes: [NSButton] = []
    private var layoutIDs: [String] = []
    private var layoutNames: [String] = []
    private var modeSelector: NSSegmentedControl!
    private var sourcePopup: NSPopUpButton!
    private var targetPopup: NSPopUpButton!
    private var hotkeyTypePopup: NSPopUpButton!
    private var recorderButton: HotkeyRecorderButton!
    private var launchAtLoginCheckbox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.title")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self

        let layouts = loadAllLayouts()
        layoutIDs = layouts.map { $0.id }
        layoutNames = layouts.map { $0.name }

        buildUI()
        applyPersistedSettings()
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        var y: CGFloat = 16

        // Save button
        let saveBtn = NSButton(title: L("button.save"), target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 334, y: y, width: 90, height: 28)
        saveBtn.keyEquivalent = "\r"
        cv.addSubview(saveBtn)
        y += 50

        // ── Hotkey ──────────────────────────────────────────────
        addSectionHeader(L("settings.section.hotkey"), to: cv, y: y); y += 24

        addLabel(L("settings.hotkey.trigger"), to: cv, frame: NSRect(x: 16, y: y + 3, width: 100, height: 18))
        hotkeyTypePopup = NSPopUpButton(frame: NSRect(x: 124, y: y, width: 210, height: 26))
        hotkeyTypePopup.addItems(withTitles: [
            L("hotkey.doubleControl"),
            L("hotkey.optionSpace"),
            L("hotkey.custom")
        ])
        hotkeyTypePopup.target = self
        hotkeyTypePopup.action = #selector(hotkeyTypeChanged)
        cv.addSubview(hotkeyTypePopup)
        y += 34

        recorderButton = HotkeyRecorderButton(frame: NSRect(x: 124, y: y, width: 210, height: 26))
        recorderButton.bezelStyle = .rounded
        recorderButton.title = L("recorder.placeholder")
        cv.addSubview(recorderButton)

        let recHint = NSTextField(labelWithString: L("recorder.hint"))
        recHint.frame = NSRect(x: 340, y: y + 5, width: 90, height: 18)
        recHint.font = NSFont.systemFont(ofSize: 11)
        recHint.textColor = .tertiaryLabelColor
        cv.addSubview(recHint)
        y += 38

        // ── Toggle mode ──────────────────────────────────────────
        addSeparator(to: cv, y: y); y += 14
        addSectionHeader(L("settings.section.toggleMode"), to: cv, y: y); y += 24

        addLabel(L("settings.mode.label"), to: cv, frame: NSRect(x: 16, y: y + 3, width: 100, height: 18))
        modeSelector = NSSegmentedControl(
            labels: [L("mode.pair"), L("mode.cycle")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged)
        )
        modeSelector.frame = NSRect(x: 124, y: y, width: 300, height: 26)
        modeSelector.selectedSegment = 0
        cv.addSubview(modeSelector)
        y += 34

        addLabel(L("settings.source.label"), to: cv, frame: NSRect(x: 16, y: y + 3, width: 100, height: 18))
        sourcePopup = NSPopUpButton(frame: NSRect(x: 124, y: y, width: 300, height: 26))
        cv.addSubview(sourcePopup)
        y += 32

        addLabel(L("settings.target.label"), to: cv, frame: NSRect(x: 16, y: y + 3, width: 100, height: 18))
        targetPopup = NSPopUpButton(frame: NSRect(x: 124, y: y, width: 300, height: 26))
        cv.addSubview(targetPopup)
        y += 38

        // ── Layouts ──────────────────────────────────────────────
        addSeparator(to: cv, y: y); y += 14
        addSectionHeader(L("settings.section.layouts"), to: cv, y: y); y += 24

        let rowH: CGFloat = 22
        let docH = max(80, CGFloat(layoutIDs.count) * rowH + 8)
        let scrollH: CGFloat = min(docH + 2, 130)

        let scrollView = NSScrollView(frame: NSRect(x: 16, y: y, width: 408, height: scrollH))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let docView = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: docH))
        var checkY = docH - rowH
        for (i, name) in layoutNames.enumerated() {
            let cb = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            cb.frame = NSRect(x: 8, y: checkY, width: 374, height: 20)
            cb.tag = i
            docView.addSubview(cb)
            checkboxes.append(cb)
            checkY -= rowH
        }
        scrollView.documentView = docView
        cv.addSubview(scrollView)
        y += scrollH + 10

        // ── General ──────────────────────────────────────────────
        addSeparator(to: cv, y: y); y += 14
        addSectionHeader(L("settings.section.general"), to: cv, y: y); y += 28

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: L("settings.launchAtLogin"),
                                         target: self, action: #selector(toggleLaunchAtLogin))
        launchAtLoginCheckbox.frame = NSRect(x: 16, y: y, width: 350, height: 20)
        cv.addSubview(launchAtLoginCheckbox)
    }

    // MARK: - Helpers

    @discardableResult
    private func addLabel(_ text: String, to view: NSView, frame: NSRect) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.frame = frame
        tf.font = NSFont.systemFont(ofSize: 13)
        view.addSubview(tf)
        return tf
    }

    private func addSectionHeader(_ text: String, to view: NSView, y: CGFloat) {
        let tf = NSTextField(labelWithString: text.uppercased())
        tf.frame = NSRect(x: 16, y: y, width: 300, height: 16)
        tf.font = NSFont.boldSystemFont(ofSize: 10)
        tf.textColor = .secondaryLabelColor
        view.addSubview(tf)
    }

    private func addSeparator(to view: NSView, y: CGFloat) {
        let box = NSBox(frame: NSRect(x: 16, y: y, width: 408, height: 1))
        box.boxType = .separator
        view.addSubview(box)
    }

    // MARK: - Data

    private func loadAllLayouts() -> [(id: String, name: String)] {
        let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        guard let raw = TISCreateInputSourceList(filter, false) else { return [] }
        let list = raw.takeRetainedValue() as! [TISInputSource]
        return list.compactMap { src in
            guard
                let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID),
                let namePtr = TISGetInputSourceProperty(src, kTISPropertyLocalizedName)
            else { return nil }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            return (id, name)
        }
    }

    private func applyPersistedSettings() {
        for name in layoutNames {
            sourcePopup.addItem(withTitle: name)
            targetPopup.addItem(withTitle: name)
        }

        let savedLayouts = UserDefaults.standard.stringArray(forKey: "selectedLayouts") ?? []
        for (i, id) in layoutIDs.enumerated() {
            checkboxes[i].state = savedLayouts.contains(id) ? .on : .off
        }

        let mode = UserDefaults.standard.string(forKey: "toggleMode") ?? "pair"
        modeSelector.selectedSegment = mode == "cycle" ? 1 : 0

        if let src = UserDefaults.standard.string(forKey: "sourceLayout"),
           let idx = layoutIDs.firstIndex(of: src) { sourcePopup.selectItem(at: idx) }
        if let tgt = UserDefaults.standard.string(forKey: "targetLayout"),
           let idx = layoutIDs.firstIndex(of: tgt) { targetPopup.selectItem(at: idx) }

        updatePairVisibility()
        updateLaunchAtLoginCheckbox()

        let config = HotkeyConfig.load()
        switch config.kind {
        case .doubleTapControl:
            hotkeyTypePopup.selectItem(at: 0)
            recorderButton.isHidden = true
        case .combo(let kc, let mods):
            let modMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            if kc == 49 && mods.intersection(modMask) == .maskAlternate {
                hotkeyTypePopup.selectItem(at: 1)
            } else {
                hotkeyTypePopup.selectItem(at: 2)
            }
            recorderButton.configure(keyCode: kc, modifiers: mods)
            recorderButton.isHidden = hotkeyTypePopup.indexOfSelectedItem != 2
        }
    }

    @objc private func modeChanged() { updatePairVisibility() }

    private func updateLaunchAtLoginCheckbox() {
        let status = SMAppService.mainApp.status
        launchAtLoginCheckbox.state = (status == .enabled || status == .requiresApproval) ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // If requiresApproval — guide user
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            // Revert on failure
            updateLaunchAtLoginCheckbox()
        }
    }

    private func updatePairVisibility() {
        let isPair = modeSelector.selectedSegment == 0
        sourcePopup.isHidden = !isPair
        targetPopup.isHidden = !isPair
    }

    @objc private func hotkeyTypeChanged() {
        recorderButton.isHidden = hotkeyTypePopup.indexOfSelectedItem != 2
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    @objc private func save() {
        let selected = checkboxes.enumerated().compactMap { (i, cb) -> String? in
            cb.state == .on ? layoutIDs[i] : nil
        }
        UserDefaults.standard.set(selected, forKey: "selectedLayouts")

        let mode = modeSelector.selectedSegment == 0 ? "pair" : "cycle"
        UserDefaults.standard.set(mode, forKey: "toggleMode")

        let si = sourcePopup.indexOfSelectedItem, ti = targetPopup.indexOfSelectedItem
        if si >= 0 && si < layoutIDs.count { UserDefaults.standard.set(layoutIDs[si], forKey: "sourceLayout") }
        if ti >= 0 && ti < layoutIDs.count { UserDefaults.standard.set(layoutIDs[ti], forKey: "targetLayout") }

        let hotkeyConfig: HotkeyConfig
        switch hotkeyTypePopup.indexOfSelectedItem {
        case 0:
            hotkeyConfig = HotkeyConfig(kind: .doubleTapControl)
        case 1:
            hotkeyConfig = HotkeyConfig(kind: .combo(keyCode: 49, modifiers: .maskAlternate))
        default:
            hotkeyConfig = HotkeyConfig(kind: .combo(keyCode: recorderButton.keyCode, modifiers: recorderButton.modifiers))
        }
        hotkeyConfig.save()
        NotificationCenter.default.post(name: .hotkeyConfigChanged, object: nil)

        window?.close()
    }
}

// MARK: - Hotkey Recorder Button

class HotkeyRecorderButton: NSButton {
    private(set) var keyCode: CGKeyCode = 49
    private(set) var modifiers: CGEventFlags = [.maskAlternate]
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    func configure(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        isRecording = false
        title = displayString(keyCode: keyCode, modifiers: modifiers)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        isRecording = true
        title = L("recorder.recording")
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        if event.keyCode == 53 {
            isRecording = false
            title = displayString(keyCode: keyCode, modifiers: modifiers)
            window?.makeFirstResponder(nil)
            return
        }

        var cgMods: CGEventFlags = []
        let mods = event.modifierFlags
        if mods.contains(.command) { cgMods.insert(.maskCommand) }
        if mods.contains(.option)  { cgMods.insert(.maskAlternate) }
        if mods.contains(.control) { cgMods.insert(.maskControl) }
        if mods.contains(.shift)   { cgMods.insert(.maskShift) }
        guard !cgMods.isEmpty else { return }

        keyCode = CGKeyCode(event.keyCode)
        modifiers = cgMods
        isRecording = false
        title = displayString(keyCode: keyCode, modifiers: modifiers)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {}

    private func displayString(keyCode: CGKeyCode, modifiers: CGEventFlags) -> String {
        var s = ""
        if modifiers.contains(.maskControl)   { s += "⌃" }
        if modifiers.contains(.maskAlternate) { s += "⌥" }
        if modifiers.contains(.maskShift)     { s += "⇧" }
        if modifiers.contains(.maskCommand)   { s += "⌘" }
        s += keyCodeToChar(keyCode)
        return s
    }

    private func keyCodeToChar(_ kc: CGKeyCode) -> String {
        switch kc {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let src = CGEventSource(stateID: .hidSystemState)
            guard let ev = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: true) else {
                return "[\(kc)]"
            }
            var len = 0
            var chars = [UniChar](repeating: 0, count: 8)
            ev.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &chars)
            guard len > 0 else { return "[\(kc)]" }
            return String(chars[0..<len].compactMap { Unicode.Scalar($0) }.map { Character($0) }).uppercased()
        }
    }
}
