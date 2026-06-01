import Cocoa

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("ghbdtn.onboardingCompleted")
}

class OnboardingWindowController: NSWindowController {

    private let windowW: CGFloat = 520
    private let windowH: CGFloat = 430
    private let navH:    CGFloat = 70
    private var containerH: CGFloat { windowH - navH }

    private var currentStep = 0
    private let totalSteps = 3
    private var permissionPollTimer: Timer?

    private var containerView: NSView!
    private var stepViews: [NSView] = []
    private var nextButton: NSButton!
    private var backButton: NSButton!
    private var stepDots: [NSView] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.remove(.resizable)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    // MARK: - Build

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // Step container (clipping view)
        containerView = NSView(frame: NSRect(x: 0, y: navH, width: windowW, height: containerH))
        containerView.wantsLayer = true
        cv.addSubview(containerView)

        stepViews = [buildWelcomeStep(), buildHowItWorksStep(), buildPermissionStep()]

        for (i, v) in stepViews.enumerated() {
            v.frame = NSRect(x: i == 0 ? 0 : windowW, y: 0, width: windowW, height: containerH)
            v.wantsLayer = true
            containerView.addSubview(v)
        }

        // Navigation
        backButton = NSButton(title: "← " + L("onboarding.back"), target: self, action: #selector(goBack))
        backButton.bezelStyle = .recessed
        backButton.isBordered = false
        backButton.frame = NSRect(x: 20, y: 20, width: 110, height: 28)
        backButton.isHidden = true
        cv.addSubview(backButton)

        nextButton = NSButton(title: L("onboarding.next") + " →", target: self, action: #selector(goNext))
        nextButton.bezelStyle = .rounded
        nextButton.frame = NSRect(x: windowW - 130, y: 18, width: 110, height: 32)
        nextButton.keyEquivalent = "\r"
        cv.addSubview(nextButton)

        // Progress dots
        let dotD: CGFloat = 8
        let dotGap: CGFloat = 18
        let totalW = CGFloat(totalSteps) * dotD + CGFloat(totalSteps - 1) * (dotGap - dotD)
        var dotX = (windowW - totalW) / 2
        for i in 0..<totalSteps {
            let dot = NSView(frame: NSRect(x: dotX, y: 28, width: dotD, height: dotD))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotD / 2
            cv.addSubview(dot)
            stepDots.append(dot)
            dotX += dotGap
        }

        updateNav()
    }

    // MARK: - Steps

    private func buildWelcomeStep() -> NSView {
        let v = NSView()

        // SF Symbol keyboard icon
        let iv = NSImageView(frame: NSRect(x: (windowW - 80) / 2, y: containerH - 120, width: 80, height: 80))
        iv.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 60, weight: .light)
        iv.contentTintColor = .controlAccentColor
        iv.imageScaling = .scaleProportionallyUpOrDown
        v.addSubview(iv)

        let title = label(L("onboarding.welcome.title"), font: .boldSystemFont(ofSize: 28),
                          frame: NSRect(x: 60, y: containerH - 195, width: windowW - 120, height: 50))
        title.alignment = .center
        v.addSubview(title)

        let sub = wrapping(L("onboarding.welcome.subtitle"),
                           frame: NSRect(x: 80, y: containerH - 265, width: windowW - 160, height: 60))
        sub.alignment = .center
        sub.font = NSFont.systemFont(ofSize: 16)
        v.addSubview(sub)

        let tag = wrapping(L("onboarding.welcome.tagline"),
                           frame: NSRect(x: 80, y: containerH - 320, width: windowW - 160, height: 45))
        tag.alignment = .center
        tag.font = NSFont.systemFont(ofSize: 13)
        tag.textColor = .secondaryLabelColor
        v.addSubview(tag)

        return v
    }

    private func buildHowItWorksStep() -> NSView {
        let v = NSView()

        let title = label(L("onboarding.how.title"), font: .boldSystemFont(ofSize: 22),
                          frame: NSRect(x: 60, y: containerH - 60, width: windowW - 120, height: 35))
        title.alignment = .center
        v.addSubview(title)

        // Card: wrong text
        v.addSubview(card(frame: NSRect(x: 80, y: containerH - 155, width: windowW - 160, height: 68)))
        let num1 = badge("1", origin: NSPoint(x: 96, y: containerH - 130))
        v.addSubview(num1)
        let wrong = label("\"ghbdtn\"", font: .monospacedSystemFont(ofSize: 20, weight: .medium),
                          frame: NSRect(x: 128, y: containerH - 130, width: 220, height: 28))
        wrong.textColor = .systemRed
        v.addSubview(wrong)
        let h1 = label(L("onboarding.how.step1"), font: .systemFont(ofSize: 11),
                       frame: NSRect(x: 128, y: containerH - 150, width: 320, height: 18))
        h1.textColor = .secondaryLabelColor
        v.addSubview(h1)

        // Arrow
        let arrow = label("⌃⌃  ↓", font: .monospacedSystemFont(ofSize: 18, weight: .regular),
                          frame: NSRect(x: (windowW - 80) / 2, y: containerH - 210, width: 80, height: 28))
        arrow.alignment = .center
        arrow.textColor = .controlAccentColor
        v.addSubview(arrow)

        // Card: correct text
        v.addSubview(card(frame: NSRect(x: 80, y: containerH - 300, width: windowW - 160, height: 68)))
        let num2 = badge("2", origin: NSPoint(x: 96, y: containerH - 275))
        v.addSubview(num2)
        let right = label("\"привет\"", font: .monospacedSystemFont(ofSize: 20, weight: .medium),
                          frame: NSRect(x: 128, y: containerH - 275, width: 220, height: 28))
        right.textColor = .systemGreen
        v.addSubview(right)
        let h2 = label(L("onboarding.how.step2"), font: .systemFont(ofSize: 11),
                       frame: NSRect(x: 128, y: containerH - 295, width: 320, height: 18))
        h2.textColor = .secondaryLabelColor
        v.addSubview(h2)

        // Note
        let note = wrapping(L("onboarding.how.note"),
                            frame: NSRect(x: 80, y: 16, width: windowW - 160, height: 40))
        note.alignment = .center
        note.font = NSFont.systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        v.addSubview(note)

        return v
    }

    private func buildPermissionStep() -> NSView {
        let v = NSView()

        // Shield icon
        let iv = NSImageView(frame: NSRect(x: (windowW - 70) / 2, y: containerH - 110, width: 70, height: 70))
        iv.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
        iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 52, weight: .light)
        iv.contentTintColor = .controlAccentColor
        iv.imageScaling = .scaleProportionallyUpOrDown
        v.addSubview(iv)

        let title = label(L("onboarding.permission.title"), font: .boldSystemFont(ofSize: 20),
                          frame: NSRect(x: 60, y: containerH - 160, width: windowW - 120, height: 34))
        title.alignment = .center
        v.addSubview(title)

        let desc = wrapping(L("onboarding.permission.desc"),
                            frame: NSRect(x: 70, y: containerH - 265, width: windowW - 140, height: 95))
        desc.alignment = .center
        desc.font = NSFont.systemFont(ofSize: 14)
        desc.textColor = .secondaryLabelColor
        v.addSubview(desc)

        let grantBtn = NSButton(title: L("button.openSystemSettings"), target: self, action: #selector(openAccessibility))
        grantBtn.bezelStyle = .rounded
        grantBtn.frame = NSRect(x: (windowW - 240) / 2, y: containerH - 310, width: 240, height: 32)
        v.addSubview(grantBtn)

        // Status label (shown when granted)
        let status = NSTextField(labelWithString: "✓  " + L("onboarding.permission.granted"))
        status.frame = NSRect(x: (windowW - 220) / 2, y: containerH - 350, width: 220, height: 24)
        status.alignment = .center
        status.textColor = .systemGreen
        status.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        status.isHidden = !AXIsProcessTrusted()
        status.tag = 42
        v.addSubview(status)

        // Poll until granted; timer stored so finish() can invalidate it
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak v, weak self] timer in
            guard let v else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                v.viewWithTag(42)?.isHidden = false
                self?.nextButton.title = L("onboarding.start")
            }
        }
        permissionPollTimer = t

        return v
    }

    // MARK: - Navigation

    @objc private func goNext() {
        if currentStep == totalSteps - 1 { finish(); return }
        slide(to: currentStep + 1, dir: 1)
    }

    @objc private func goBack() {
        slide(to: currentStep - 1, dir: -1)
    }

    private func slide(to next: Int, dir: Int) {
        let old = stepViews[currentStep]
        let new = stepViews[next]
        new.frame.origin.x = dir > 0 ? windowW : -windowW
        new.alphaValue = 0

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            old.animator().alphaValue = 0
            old.animator().frame.origin.x = dir > 0 ? -windowW : windowW
            new.animator().alphaValue = 1
            new.animator().frame.origin.x = 0
        }, completionHandler: {
            old.alphaValue = 1
        })

        currentStep = next
        updateNav()
    }

    private func updateNav() {
        backButton.isHidden = currentStep == 0

        if currentStep == totalSteps - 1 {
            nextButton.title = AXIsProcessTrusted() ? L("onboarding.start") : L("onboarding.skip")
        } else {
            nextButton.title = L("onboarding.next") + " →"
        }

        for (i, dot) in stepDots.enumerated() {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                dot.animator().layer?.backgroundColor =
                    (i == currentStep ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
            }
        }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func finish() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        window?.close()
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }

    // MARK: - Factory helpers

    private func label(_ text: String, font: NSFont, frame: NSRect) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.frame = frame
        tf.font = font
        return tf
    }

    private func wrapping(_ text: String, frame: NSRect) -> NSTextField {
        let tf = NSTextField(wrappingLabelWithString: text)
        tf.frame = frame
        return tf
    }

    private func card(frame: NSRect) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        v.layer?.cornerRadius = 10
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor.separatorColor.cgColor
        return v
    }

    private func badge(_ text: String, origin: NSPoint) -> NSView {
        let size: CGFloat = 22
        let v = NSView(frame: NSRect(origin: origin, size: NSSize(width: size, height: size)))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        v.layer?.cornerRadius = size / 2

        let tf = NSTextField(labelWithString: text)
        tf.frame = NSRect(x: 0, y: 2, width: size, height: size - 2)
        tf.font = NSFont.boldSystemFont(ofSize: 12)
        tf.alignment = .center
        tf.textColor = .controlAccentColor
        v.addSubview(tf)
        return v
    }
}
