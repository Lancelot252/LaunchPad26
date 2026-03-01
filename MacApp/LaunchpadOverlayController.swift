import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settingsStore = LaunchpadSettingsStore()
    private let presentationModel = LaunchpadPresentationModel()
    private var overlayController: LaunchpadOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = LaunchpadOverlayController(
            presentationModel: presentationModel,
            settingsStore: settingsStore,
            onOpenSettingsWindow: { [weak self] in
                self?.openSettingsWindow()
            }
        )
        overlayController?.start()
    }

    @objc func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

final class LaunchpadPresentationModel {
    var isEditing: Bool = false
    var focusToken = UUID()
}

final class LaunchpadOverlayController {
    private let presentationModel: LaunchpadPresentationModel
    private let settingsStore: LaunchpadSettingsStore
    private let onOpenSettingsWindow: () -> Void
    private var window: LaunchpadOverlayWindow?
    private var hostView: NSHostingView<ContentView>?
    private var hideWorkItem: DispatchWorkItem?
    private var resignObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var hotkeyManager: GlobalHotkeyManager?

    init(
        presentationModel: LaunchpadPresentationModel,
        settingsStore: LaunchpadSettingsStore,
        onOpenSettingsWindow: @escaping () -> Void
    ) {
        self.presentationModel = presentationModel
        self.settingsStore = settingsStore
        self.onOpenSettingsWindow = onOpenSettingsWindow
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func start() {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.settingsStore.current.hideOnResignActive else { return }
            self.hide(animated: true)
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: LaunchpadSettingsStore.didChangeNotification,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }

        applySettings()
        show(animated: false)
    }

    func toggle() {
        if let window, window.isVisible {
            hide(animated: true)
        } else {
            show(animated: true)
        }
    }

    func show(animated: Bool) {
        hideWorkItem?.cancel()
        let window = ensureWindow()
        let screenFrame = activeScreenFrame()
        window.setFrame(screenFrame, display: true)
        let shouldAnimate = animated && settingsStore.current.enableAnimations

        presentationModel.focusToken = UUID()
        hostView?.rootView = makeRootView()

        if !shouldAnimate {
            window.alphaValue = 1
            hostView?.layer?.transform = CATransform3DIdentity
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        window.alphaValue = 0
        hostView?.layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            hostView?.animator().layer?.transform = CATransform3DIdentity
        }
    }

    func hide(animated: Bool) {
        hideWorkItem?.cancel()
        guard let window, window.isVisible else { return }
        let shouldAnimate = animated && settingsStore.current.enableAnimations

        presentationModel.isEditing = false

        if !shouldAnimate {
            window.orderOut(nil)
            window.alphaValue = 1
            hostView?.layer?.transform = CATransform3DIdentity
            return
        }

        let workItem = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else { return }
            window.orderOut(nil)
            window.alphaValue = 1
            self.hostView?.layer?.transform = CATransform3DIdentity
        }
        hideWorkItem = workItem

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            hostView?.animator().layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    private func ensureWindow() -> LaunchpadOverlayWindow {
        if let window {
            return window
        }

        let frame = activeScreenFrame()
        let window = LaunchpadOverlayWindow(contentRect: frame)
        window.collectionBehavior = [.moveToActiveSpace]
        window.level = .statusBar
        window.isReleasedWhenClosed = false

        let hostView = NSHostingView(rootView: makeRootView())
        hostView.wantsLayer = true

        window.contentView = hostView

        self.window = window
        self.hostView = hostView
        return window
    }

    private func makeRootView() -> ContentView {
        ContentView(
            onDismiss: { [weak self] in self?.hide(animated: true) },
            onLaunchApp: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.hide(animated: true)
            },
            onResetLayout: { },
            onOpenSettings: { [weak self] in
                self?.onOpenSettingsWindow()
            },
            settingsStore: settingsStore,
            isEditing: Binding(
                get: { [weak self] in self?.presentationModel.isEditing ?? false },
                set: { [weak self] in self?.presentationModel.isEditing = $0 }
            ),
            focusToken: presentationModel.focusToken
        )
    }

    private func activeScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen.frame
        }
        return NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
    }

    func applySettings() {
        rebindHotKeyIfNeeded()
    }

    func rebindHotKeyIfNeeded() {
        hotkeyManager = nil

        let preset = settingsStore.current.hotkeyPreset
        hotkeyManager = GlobalHotkeyManager(
            keyCode: preset.keyCode,
            modifiers: preset.modifiers
        ) { [weak self] in
            self?.toggle()
        }
    }
}

final class LaunchpadOverlayWindow: NSWindow {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

final class GlobalHotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let callback: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let eventHandlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == manager.signature else {
                    return noErr
                }

                manager.callback()
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard eventHandlerStatus == noErr else {
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            return nil
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private var signature: OSType {
        0x4C504844 // "LPHD"
    }
}
