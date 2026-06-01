import Cocoa
import Carbon
import CoreGraphics

// MARK: - Hotkey Config

struct HotkeyConfig {
    enum Kind {
        case doubleTapControl
        case combo(keyCode: CGKeyCode, modifiers: CGEventFlags)
    }
    var kind: Kind

    static func load() -> HotkeyConfig {
        let type = UserDefaults.standard.string(forKey: "hotkeyType") ?? "double_control"
        if type == "double_control" {
            return HotkeyConfig(kind: .doubleTapControl)
        }
        let kc = CGKeyCode(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let rawMods = UInt64(bitPattern: Int64(UserDefaults.standard.integer(forKey: "hotkeyModifiers")))
        return HotkeyConfig(kind: .combo(keyCode: kc, modifiers: CGEventFlags(rawValue: rawMods)))
    }

    func save() {
        switch kind {
        case .doubleTapControl:
            UserDefaults.standard.set("double_control", forKey: "hotkeyType")
        case .combo(let kc, let mods):
            UserDefaults.standard.set("combo", forKey: "hotkeyType")
            UserDefaults.standard.set(Int(kc), forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int64(bitPattern: mods.rawValue), forKey: "hotkeyModifiers")
        }
    }
}

extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("ghbdtn.hotkeyConfigChanged")
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var tapRunLoopSource: CFRunLoopSource?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var hotkeyConfig = HotkeyConfig.load()

    // Double-tap state
    private var ctrlLastPressTime: TimeInterval = 0
    private var ctrlIsDown = false

    // Prevent concurrent translations
    private var isTranslating = false

    // Watchdog: revive dead event tap
    private var tapWatchdogTimer: Timer?

    // Layout map: Russian QWERTY ↔ English QWERTY (same physical key)
    private let ruToEn: [Character: Character] = [
        "й":"q","ц":"w","у":"e","к":"r","е":"t","н":"y","г":"u","ш":"i","щ":"o","з":"p","х":"[","ъ":"]",
        "ф":"a","ы":"s","в":"d","а":"f","п":"g","р":"h","о":"j","л":"k","д":"l","ж":";","э":"'",
        "я":"z","ч":"x","с":"c","м":"v","и":"b","т":"n","ь":"m","б":",","ю":".",
        "Й":"Q","Ц":"W","У":"E","К":"R","Е":"T","Н":"Y","Г":"U","Ш":"I","Щ":"O","З":"P","Х":"{","Ъ":"}",
        "Ф":"A","Ы":"S","В":"D","А":"F","П":"G","Р":"H","О":"J","Л":"K","Д":"L","Ж":":","Э":"\"",
        "Я":"Z","Ч":"X","С":"C","М":"V","И":"B","Т":"N","Ь":"M","Б":"<","Ю":">"
    ]

    private lazy var enToRu: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (ru, en) in ruToEn { map[en] = ru }
        return map
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadHotkey), name: .hotkeyConfigChanged, object: nil)

        if UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
            checkAccessibilityPermission()
            checkLayoutsAndSetup()
        } else {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(forName: .onboardingCompleted, object: nil, queue: .main) { [weak self] _ in
            self?.onboardingWindowController = nil // free window + all its views
            self?.checkAccessibilityPermission()
            self?.checkLayoutsAndSetup()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(appMenuItem)
    }

    private func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            let keyPath = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11), xRadius: 2, yRadius: 2)
            keyPath.lineWidth = 1.5
            keyPath.stroke()
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 4, y: 9))
            arrow.line(to: NSPoint(x: 6.5, y: 7))
            arrow.line(to: NSPoint(x: 6.5, y: 8.3))
            arrow.line(to: NSPoint(x: 11.5, y: 8.3))
            arrow.line(to: NSPoint(x: 11.5, y: 7))
            arrow.line(to: NSPoint(x: 14, y: 9))
            arrow.line(to: NSPoint(x: 11.5, y: 11))
            arrow.line(to: NSPoint(x: 11.5, y: 9.7))
            arrow.line(to: NSPoint(x: 6.5, y: 9.7))
            arrow.line(to: NSPoint(x: 6.5, y: 11))
            arrow.close()
            arrow.fill()
            return true
        }
        return image
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        if AXIsProcessTrustedWithOptions(options) {
            installEventTap()
        } else {
            showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = L("accessibility.title")
        alert.informativeText = L("accessibility.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("button.openSystemSettings"))
        alert.addButton(withTitle: L("button.later"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.installEventTap()
            }
        }
    }

    // MARK: - Layouts

    private func checkLayoutsAndSetup() {
        let sources = installedInputSources()
        if sources.count < 2 {
            let alert = NSAlert()
            alert.messageText = L("layouts.insufficient.title")
            alert.informativeText = L("layouts.insufficient.message")
            alert.addButton(withTitle: L("button.ok"))
            alert.runModal()
        } else if sources.count == 2 {
            UserDefaults.standard.set(sources, forKey: "selectedLayouts")
            UserDefaults.standard.set("pair", forKey: "toggleMode")
            UserDefaults.standard.set(sources[0], forKey: "sourceLayout")
            UserDefaults.standard.set(sources[1], forKey: "targetLayout")
        } else {
            if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                openSettings()
            }
        }
    }

    private func installedInputSources() -> [String] {
        let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        guard let raw = TISCreateInputSourceList(filter, false) else { return [] }
        let list = raw.takeRetainedValue() as! [TISInputSource]
        return list.compactMap { src in
            guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }
    }

    // MARK: - Event Tap

    @objc private func reloadHotkey() {
        hotkeyConfig = HotkeyConfig.load()
        reinstallEventTap()
    }

    private func reinstallEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = tapRunLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        tapRunLoopSource = nil
        installEventTap()
    }

    private func installEventTap() {
        var mask: CGEventMask = 0
        switch hotkeyConfig.kind {
        case .doubleTapControl:
            mask = 1 << CGEventType.flagsChanged.rawValue
        case .combo:
            mask = 1 << CGEventType.keyDown.rawValue
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let me = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return me.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Watchdog: if tap is invalidated (accessibility revoked), revive it
        tapWatchdogTimer?.invalidate()
        tapWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                if AXIsProcessTrusted() {
                    self.reinstallEventTap()
                }
            }
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch hotkeyConfig.kind {
        case .doubleTapControl:
            return handleDoubleTap(type: type, event: event)
        case .combo(let keyCode, let mods):
            return handleCombo(keyCode: keyCode, mods: mods, type: type, event: event)
        }
    }

    private func handleDoubleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passRetained(event) }
        let flags = event.flags
        let ctrlNow = flags.contains(.maskControl)

        if ctrlNow && !ctrlIsDown {
            let now = ProcessInfo.processInfo.systemUptime
            if now - ctrlLastPressTime < 0.4 {
                ctrlLastPressTime = 0
                DispatchQueue.main.async { [weak self] in self?.performLayoutTranslation() }
            } else {
                ctrlLastPressTime = now
            }
            ctrlIsDown = true
        } else if !ctrlNow && ctrlIsDown {
            ctrlIsDown = false
        }

        return Unmanaged.passRetained(event)
    }

    private func handleCombo(keyCode: CGKeyCode, mods: CGEventFlags, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let evKC = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard evKC == keyCode && event.flags.intersection(modMask) == mods.intersection(modMask) else {
            return Unmanaged.passRetained(event)
        }

        DispatchQueue.main.async { [weak self] in self?.performLayoutTranslation() }
        return nil
    }

    // MARK: - Translation

    private func performLayoutTranslation() {
        guard !isTranslating else { return }
        isTranslating = true

        let pb = NSPasteboard.general

        var savedContents: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pb.types ?? [] {
            if let data = pb.data(forType: type) { savedContents[type] = data }
        }

        pb.clearContents()
        simulateKey(keyCode: 8, flags: .maskCommand) // ⌘C

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            defer { DispatchQueue.main.async { self.isTranslating = false } }

            Thread.sleep(forTimeInterval: 0.1)

            // Read clipboard on a background-safe way — NSPasteboard is main-thread only
            var copied: String? = nil
            DispatchQueue.main.sync { copied = pb.string(forType: .string) }

            guard let text = copied, !text.isEmpty else {
                DispatchQueue.main.async { self.restoreClipboard(savedContents, pb: pb) }
                return
            }

            let translated = self.translateString(text)
            guard translated != text else {
                DispatchQueue.main.async { self.restoreClipboard(savedContents, pb: pb) }
                return
            }

            DispatchQueue.main.sync {
                pb.clearContents()
                pb.setString(translated, forType: .string)
            }

            Thread.sleep(forTimeInterval: 0.05)
            self.simulateKey(keyCode: 9, flags: .maskCommand) // ⌘V
            Thread.sleep(forTimeInterval: 0.1)

            DispatchQueue.main.async { self.restoreClipboard(savedContents, pb: pb) }
        }
    }

    private func restoreClipboard(_ contents: [NSPasteboard.PasteboardType: Data], pb: NSPasteboard) {
        pb.clearContents()
        for (type, data) in contents { pb.setData(data, forType: type) }
    }

    private func simulateKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let dn = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        dn?.flags = flags; up?.flags = flags
        dn?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // Per-character bidirectional translation
    private func translateString(_ text: String) -> String {
        String(text.map { ch in
            if let mapped = ruToEn[ch] { return mapped }
            if let mapped = enToRu[ch] { return mapped }
            return ch
        })
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindowController == nil {
            let wc = SettingsWindowController()
            wc.onClose = { [weak self] in self?.settingsWindowController = nil }
            settingsWindowController = wc
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Localization helper

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
