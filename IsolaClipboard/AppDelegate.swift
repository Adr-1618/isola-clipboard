import AppKit
import Carbon.HIToolbox
import QuartzCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private weak var toggleMenuItem: NSMenuItem?
    private var islandController: IslandPanelController?
    private var settingsWindow: NSWindow?
    private let preferences = AppPreferences.shared
    private let loginSettings = LoginItemSettings()
    private let shortcutManager = GlobalShortcutManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains(where: { $0.processIdentifier != currentPID }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)

        let controller = IslandPanelController(preferences: preferences)
        islandController = controller
        shortcutManager.onActivate = { [weak controller] in
            controller?.logDragDiagnostics("shortcutTriggered", detail: "")
            controller?.toggle()
        }
        shortcutManager.onOpenSettings = { [weak self] in self?.openSettings(nil) }
        shortcutManager.register(keyCode: preferences.shortcutKeyCode, modifiers: preferences.shortcutModifiers)
        controller.logDragDiagnostics(
            "shortcutRegistration",
            detail: "keyCode=\(preferences.shortcutKeyCode) modifiers=\(preferences.shortcutModifiers) status=\(shortcutManager.registrationError ?? noErr)"
        )

        ClipboardHistory.shared.onNewItem = { [weak controller, preferences] in
            if preferences.openAfterCopy { controller?.open() }
        }
        ClipboardHistory.shared.start()

        updateStatusItemVisibility()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        controller.prepareCollapsedIsland()
#if ISOLA_DIAGNOSTIC_BUILD
        controller.open()
#endif
    }

    private func updateStatusItemVisibility() {
        guard preferences.showMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            islandController?.setStatusItem(button: nil)
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let symbol = NSImage(systemSymbolName: "document.on.clipboard", accessibilityDescription: "Isola Clipboard") {
            symbol.isTemplate = true
            item.button?.image = symbol
        } else {
            item.button?.title = "IC"
        }
        item.button?.target = self
        item.button?.action = #selector(statusItemAction(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Isola Clipboard"
        statusItem = item
        buildStatusMenu()
        islandController?.setStatusItem(button: item.button)
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        islandController?.screensChanged()
    }

    @objc private func statusItemAction(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp else {
            islandController?.toggle()
            return
        }
        guard let statusMenu else { return }
        if let toggleMenuItem { toggleMenuItem.title = islandController?.isVisible == true ? "Nascondi Isola" : "Mostra Isola" }
        NSMenu.popUpContextMenu(statusMenu, with: event, for: sender)
    }

    private func buildStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let toggleItem = menu.addItem(withTitle: "Mostra Isola", action: #selector(toggleIsland(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleMenuItem = toggleItem
        menu.addItem(withTitle: "Impostazioni…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        menu.addItem(withTitle: "Svuota cronologia…", action: #selector(clearHistory(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Esci da Isola Clipboard", action: #selector(terminateApplication(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusMenu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { islandController?.setStatusMenuTracking(true) }
    func menuDidClose(_ menu: NSMenu) { islandController?.setStatusMenuTracking(false) }

    @objc private func toggleIsland(_ sender: Any?) { islandController?.toggle() }

    @objc private func clearHistory(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Svuotare la cronologia?"
        alert.informativeText = "Gli elementi conservati in memoria verranno rimossi."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Svuota cronologia")
        alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ClipboardHistory.shared.clear()
    }

    @objc private func openSettings(_ sender: Any?) {
        loginSettings.refresh()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Isola Clipboard · Impostazioni"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(
                preferences: preferences,
                loginSettings: loginSettings,
                history: .shared,
                onPreferencesChanged: { [weak self] in
                    guard let self else { return }
                    self.islandController?.refreshSettings()
                    self.updateStatusItemVisibility()
                    self.shortcutManager.register(keyCode: self.preferences.shortcutKeyCode, modifiers: self.preferences.shortcutModifiers)
                },
                onCaptureShortcut: { [weak self] keyCode, modifiers in
                    self?.preferences.shortcutKeyCode = keyCode
                    self?.preferences.shortcutModifiers = modifiers
                    self?.shortcutManager.register(keyCode: keyCode, modifiers: modifiers)
                }
            ))
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func terminateApplication(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private enum IslandPresentationState: Equatable {
    case hidden
    case opening
    case visible
    case closing
}

@MainActor
private final class IslandPresentationModel: ObservableObject {
    @Published var state: IslandPresentationState = .hidden
    @Published var size = CGSize(width: 74, height: 16)
    @Published var tileSide: CGFloat = 64
    @Published var tileWidth: CGFloat = 68
    @Published var tileLineCount = 1
    @Published var reduceMotion = false
}

@MainActor
private final class IslandPanelController: NSObject {
    private let panel: NSPanel
    private let preferences: AppPreferences
    private let diagnosticAutoDismissDisabled: Bool
#if ISOLA_DIAGNOSTIC_BUILD
    private let diagnosticAutomationBuild = true
#else
    private let diagnosticAutomationBuild = false
#endif
    private let presentation = IslandPresentationModel()
    private var dismissWorkItem: DispatchWorkItem?
    private var closeFallbackWorkItem: DispatchWorkItem?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var activatedAppObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    private weak var statusItemButton: NSStatusBarButton?
    private var statusMenuIsTracking = false
    private var isHoveringThumbnail = false
    private var isPointerDownOnItem = false
    private var isDragStarting = false
    private var isDragging = false
    private var presentationGeneration = 0
    private weak var activeScreen: NSScreen?
    private let collapsedSize = CGSize(width: 74, height: 16)
    private let maximumSize = CGSize(width: 500, height: 120)
    var isVisible: Bool { presentation.state == .visible || presentation.state == .opening }
    private var isDragInteractionActive: Bool { isDragStarting || isDragging }
    private var isInteractionHeld: Bool { isHoveringThumbnail || isPointerDownOnItem || isDragInteractionActive }

    func setStatusItem(button: NSStatusBarButton?) {
        statusItemButton = button
    }

    func setStatusMenuTracking(_ isTracking: Bool) {
        statusMenuIsTracking = isTracking
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
#if ISOLA_DIAGNOSTIC_BUILD
        diagnosticAutoDismissDisabled = true
#else
        diagnosticAutoDismissDisabled = ProcessInfo.processInfo.arguments.contains("--diagnostic-no-autoclose")
#endif
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        let hostingView = NSHostingView(rootView: IslandView(
            history: .shared,
            presentation: presentation,
            preferences: preferences,
            onToggle: { [weak self] in self?.toggle() },
            onSelect: { [weak self] entry in
                if self?.diagnosticAutoDismissDisabled == true {
                    self?.logDragDiagnostics("tileClickNoCopy", detail: "content=\(entry.dragContentType)")
                    return
                }
                ClipboardHistory.shared.copyToPasteboard(entry)
                self?.scheduleDismissal()
            },
            onHover: { [weak self] inside in self?.setHoveringItem(inside) },
            onPointerDown: { [weak self] pressed in self?.setPointerDown(pressed) },
            onDragStarting: { [weak self] starting in self?.setDragStarting(starting) },
            onDragChanged: { [weak self] dragging, operation in self?.setDragging(dragging, operation: operation) },
            onDragDiagnostic: { [weak self] event, detail in self?.logDragDiagnostics(event, detail: detail) },
            onResize: { [weak self] count in self?.resize(for: count) }
        ))
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        installDismissalMonitors()
        if diagnosticAutoDismissDisabled {
            logDragDiagnostics("diagnosticMode", detail: "automaticDismissal=disabled")
        }
    }

    func prepareCollapsedIsland() {
        guard let screen = preferredScreen() else { return }
        activeScreen = screen
        presentation.size = collapsedSize
        panel.setFrame(frame(size: collapsedSize, on: screen), display: false)
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        logPresentation("prepared-hidden", targetFrame: panel.frame)
    }

    func toggle() {
        switch presentation.state {
        case .hidden, .closing: open()
        case .opening, .visible: close(reason: "toggle")
        }
    }

    func open() {
        dismissWorkItem?.cancel()
        closeFallbackWorkItem?.cancel()
        presentationGeneration += 1
        let generation = presentationGeneration
        let wasCollapsed = presentation.state == .hidden
        let screen = preferredScreen() ?? activeScreen
        guard let screen else { return }
        activeScreen = screen
        let count = ClipboardHistory.shared.entries.count
        let expandedSize = targetSize(for: count, on: screen)
        presentation.tileSide = tileSide(for: count, on: screen)
        presentation.tileWidth = tileWidth(for: count, on: screen)
        presentation.tileLineCount = tileLineCount(for: count, on: screen)
        if wasCollapsed {
            presentation.size = collapsedSize
            panel.setFrame(frame(size: collapsedSize, on: screen), display: false)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        panel.ignoresMouseEvents = false
        presentation.size = expandedSize
        isHoveringThumbnail = false
        isDragStarting = false
        isDragging = false
        presentation.state = .opening
        let targetFrame = frame(size: expandedSize, on: screen)
        let duration = motionReduced ? 0 : 0.36
        logPresentation("open-start", targetFrame: targetFrame)
        animatePanel(to: targetFrame, duration: duration, spring: !motionReduced) { [weak self] in
            guard let self, self.presentationGeneration == generation,
                  self.presentation.state == .opening else { return }
            // Snap to the exact final AppKit bounds after implicit animation. This keeps
            // the SwiftUI host and panel in sync if another resize arrived mid-flight.
            self.applyPanelFrame(targetFrame, display: true)
            self.presentation.state = .visible
            self.logPresentation("open-complete", targetFrame: targetFrame)
        }
        scheduleDismissal()
    }

    private func close(reason: String) {
        logDragDiagnostics("dismissRequested", detail: reason)
        guard !isDragInteractionActive && !isPointerDownOnItem else {
            logDragDiagnostics("dismissSuppressed", detail: "reason=\(reason) drag=\(isDragInteractionActive) pointerDown=\(isPointerDownOnItem)")
            return
        }
        dismissWorkItem?.cancel()
        if presentation.state == .hidden {
            if panel.isVisible { closeImmediately(reason: "hidden-state-visible-panel") }
            else { panel.ignoresMouseEvents = true }
            return
        }
        guard presentation.state != .closing else { return }
        presentationGeneration += 1
        let generation = presentationGeneration
        presentation.state = .closing
        panel.ignoresMouseEvents = true
        let duration = motionReduced ? 0 : 0.20
        if let screen = activeScreen ?? preferredScreen() {
            presentation.size = collapsedSize
            let targetFrame = frame(size: collapsedSize, on: screen)
            logPresentation("close-start-\(reason)", targetFrame: targetFrame)
            let fallback = DispatchWorkItem { [weak self] in
                self?.finishClosing(generation: generation, reason: "animation-timeout")
            }
            closeFallbackWorkItem = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.45, execute: fallback)
            animatePanel(to: targetFrame, duration: duration, spring: false) { [weak self] in
                self?.finishClosing(generation: generation, reason: "animation-complete")
            }
        } else {
            finishClosing(generation: generation, reason: "no-screen")
        }
    }

    private var collapsedFrame: NSRect {
        guard let screen = activeScreen ?? preferredScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: panel.frame.midX - collapsedSize.width / 2,
                          y: panel.frame.maxY - collapsedSize.height,
                          width: collapsedSize.width,
                          height: collapsedSize.height)
        }
        return frame(size: collapsedSize, on: screen)
    }

    private func finishClosing(generation: Int, reason: String) {
        guard presentationGeneration == generation, presentation.state == .closing else { return }
        closeFallbackWorkItem?.cancel()
        closeFallbackWorkItem = nil
        let targetFrame = collapsedFrame
        applyPanelFrame(targetFrame, display: true)
        presentation.size = collapsedSize
        isHoveringThumbnail = false
        isDragStarting = false
        isDragging = false
        presentation.state = .hidden
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
        logPresentation("close-\(reason)", targetFrame: targetFrame)
        logDragDiagnostics("dismissCompleted", detail: "reason=\(reason)")
    }

    private func closeImmediately(reason: String) {
        logDragDiagnostics("dismissRequested", detail: reason)
        guard !isDragInteractionActive && !isPointerDownOnItem else {
            logDragDiagnostics("dismissSuppressed", detail: "reason=\(reason) drag=\(isDragInteractionActive) pointerDown=\(isPointerDownOnItem)")
            return
        }
        dismissWorkItem?.cancel()
        closeFallbackWorkItem?.cancel()
        guard presentation.state != .hidden || panel.isVisible else {
            panel.ignoresMouseEvents = true
            return
        }
        presentationGeneration += 1
        let generation = presentationGeneration
        presentation.state = .closing
        let targetFrame = collapsedFrame
        applyPanelFrame(targetFrame, display: false)
        finishClosing(generation: generation, reason: reason)
    }

    private func installDismissalMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.preferences.closeOnOutsideClick, self.isPresented, !self.isStatusItemInteraction,
                  !self.isEventInsidePanel(event) else { return event }
            if self.diagnosticAutomationBuild {
                self.logDragDiagnostics("dismissRequested", detail: "reason=outside-click-local diagnosticSuppressed=true")
                return event
            }
            guard !self.isDragInteractionActive && !self.isPointerDownOnItem else {
                self.logDragDiagnostics("dismissRequested", detail: "reason=outside-click-local suppressedByDrag=true")
                return event
            }
            self.closeImmediately(reason: "outside-click-local")
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.closeOnOutsideClick, self.isPresented, !self.isStatusItemInteraction,
                      !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                if self.diagnosticAutomationBuild {
                    self.logDragDiagnostics("dismissRequested", detail: "reason=outside-click-global diagnosticSuppressed=true")
                    return
                }
                guard !self.isDragInteractionActive && !self.isPointerDownOnItem else {
                    self.logDragDiagnostics("dismissRequested", detail: "reason=outside-click-global suppressedByDrag=true")
                    return
                }
                self.closeImmediately(reason: "outside-click-global")
            }
        }
        activatedAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard self.preferences.closeOnOutsideClick, self.isPresented else { return }
                if self.diagnosticAutomationBuild {
                    self.logDragDiagnostics("dismissRequested", detail: "reason=application-changed diagnosticSuppressed=true")
                    return
                }
                guard !self.isDragInteractionActive && !self.isPointerDownOnItem else {
                    self.logDragDiagnostics("dismissRequested", detail: "reason=application-changed suppressedByDrag=true")
                    return
                }
                guard
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self.closeImmediately(reason: "application-changed")
            }
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.closeOnOutsideClick, self.isPresented else { return }
                if self.diagnosticAutomationBuild {
                    self.logDragDiagnostics("dismissRequested", detail: "reason=application-resigned-active diagnosticSuppressed=true")
                    return
                }
                guard !self.isDragInteractionActive && !self.isPointerDownOnItem else {
                    self.logDragDiagnostics("dismissRequested", detail: "reason=application-resigned-active suppressedByDrag=true")
                    return
                }
                self.closeImmediately(reason: "application-resigned-active")
            }
        }
    }

    private var isPresented: Bool {
        presentation.state == .opening || presentation.state == .visible || presentation.state == .closing
    }

    private var isStatusItemInteraction: Bool {
        if statusMenuIsTracking { return true }
        guard let button = statusItemButton, let window = button.window else { return false }
        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonRectInWindow).contains(NSEvent.mouseLocation)
    }

    private func isEventInsidePanel(_ event: NSEvent) -> Bool {
        if event.window === panel { return true }
        if let eventWindow = event.window {
            let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
            return panel.frame.contains(screenPoint)
        }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    deinit {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let activatedAppObserver { NSWorkspace.shared.notificationCenter.removeObserver(activatedAppObserver) }
        if let resignActiveObserver { NotificationCenter.default.removeObserver(resignActiveObserver) }
    }

    private func logPresentation(_ event: String, targetFrame: NSRect) {
        let host = panel.contentView
        let hostFrame = host?.frame ?? .zero
        let hostBounds = host?.bounds ?? .zero
        let hostFittingSize = host?.fittingSize ?? .zero
        NSLog("[IsolaClipboard] %@ state=%@ entries=%ld tileSide=%.1f tileWidth=%.1f tileLines=%ld presentationSize=%@ panelVisible=%@ ignoresMouseEvents=%@ panelAlpha=%.2f panelOpaque=%@ panelFrame=%@ hostFrame=%@ hostBounds=%@ hostFittingSize=%@ hostHidden=%@ hiddenAncestor=%@ defaultClipping=%@ hostLayerOpaque=%@ target=%@ animations=%@",
              event,
              String(describing: presentation.state),
              ClipboardHistory.shared.entries.count,
              presentation.tileSide,
              presentation.tileWidth,
              presentation.tileLineCount,
              NSStringFromSize(presentation.size),
              panel.isVisible.description,
              panel.ignoresMouseEvents.description,
              panel.alphaValue,
              panel.isOpaque.description,
              NSStringFromRect(panel.frame),
              NSStringFromRect(hostFrame),
              NSStringFromRect(hostBounds),
              NSStringFromSize(hostFittingSize),
              (host?.isHidden ?? true).description,
              (host?.isHiddenOrHasHiddenAncestor ?? true).description,
              (host?.wantsDefaultClipping ?? true).description,
              (host?.layer?.isOpaque ?? false).description,
              NSStringFromRect(targetFrame),
              motionReduced ? "off" : "on")

        let diagnosticLine = String(
            format: "%.3f event=%@ state=%@ visible=%@ ignoresMouse=%@ panelFrame=%@ targetFrame=%@ size=%@\n",
            Date().timeIntervalSince1970,
            event,
            String(describing: presentation.state),
            panel.isVisible.description,
            panel.ignoresMouseEvents.description,
            NSStringFromRect(panel.frame),
            NSStringFromRect(targetFrame),
            NSStringFromSize(presentation.size)
        )
        let diagnosticURL = URL(fileURLWithPath: "/private/tmp/IsolaClipboard-panel-diagnostics.log")
        if !FileManager.default.fileExists(atPath: diagnosticURL.path) {
            FileManager.default.createFile(atPath: diagnosticURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: diagnosticURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(diagnosticLine.utf8))
            try? handle.close()
        }
    }

    private func resize(for entryCount: Int) {
        guard let screen = activeScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = targetSize(for: entryCount, on: screen)
        presentation.size = size
        presentation.tileSide = tileSide(for: entryCount, on: screen)
        presentation.tileWidth = tileWidth(for: entryCount, on: screen)
        presentation.tileLineCount = tileLineCount(for: entryCount, on: screen)
        if panel.isVisible, (presentation.state == .visible || presentation.state == .opening) {
            animatePanel(to: frame(size: size, on: screen), duration: 0.18, spring: false)
        }
    }

    private func setHoveringItem(_ hovering: Bool) {
        isHoveringThumbnail = hovering
        updateInteractionTimer()
    }

    private func setDragStarting(_ starting: Bool) {
        isDragStarting = starting
        if starting { dismissWorkItem?.cancel() }
        updateInteractionTimer()
    }

    private func setDragging(_ dragging: Bool, operation: NSDragOperation?) {
        isDragging = dragging
        if dragging { isDragStarting = false }
        if dragging {
            dismissWorkItem?.cancel()
        } else {
            isDragStarting = false
            if let operation {
                logDragDiagnostics("dropOperation", detail: "rawValue=\(operation.rawValue)")
            }
            logDragDiagnostics("dragEnd", detail: "operation=\(operation?.rawValue.description ?? "unknown")")
        }
        updateInteractionTimer()
    }

    fileprivate func logDragDiagnostics(_ event: String, detail: String) {
        NSLog("[IsolaClipboard] %@ %@ state=%@ dragStarting=%@ isDragging=%@ pointerDown=%@ panelVisible=%@ ignoresMouseEvents=%@ panelFrame=%@",
              event,
              detail,
              String(describing: presentation.state),
              isDragStarting.description,
              isDragging.description,
              isPointerDownOnItem.description,
              panel.isVisible.description,
              panel.ignoresMouseEvents.description,
              NSStringFromRect(panel.frame))

        let diagnosticLine = String(
            format: "%.3f event=%@ detail=%@ state=%@ dragStarting=%@ isDragging=%@ pointerDown=%@ visible=%@ ignoresMouse=%@ frame=%@\n",
            Date().timeIntervalSince1970,
            event,
            detail,
            String(describing: presentation.state),
            isDragStarting.description,
            isDragging.description,
            isPointerDownOnItem.description,
            panel.isVisible.description,
            panel.ignoresMouseEvents.description,
            NSStringFromRect(panel.frame)
        )
        let diagnosticURL = URL(fileURLWithPath: "/private/tmp/IsolaClipboard-panel-diagnostics.log")
        if !FileManager.default.fileExists(atPath: diagnosticURL.path) {
            FileManager.default.createFile(atPath: diagnosticURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: diagnosticURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(diagnosticLine.utf8))
            try? handle.close()
        }
    }

    private func setPointerDown(_ pressed: Bool) {
        isPointerDownOnItem = pressed
        logDragDiagnostics(pressed ? "itemPointerDown" : "itemPointerUp", detail: "")
        updateInteractionTimer()
    }

    private func updateInteractionTimer() {
        if isInteractionHeld { dismissWorkItem?.cancel() }
        else { scheduleDismissal() }
    }

    func refreshSettings() {
        resize(for: ClipboardHistory.shared.entries.count)
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissWorkItem?.cancel()
        guard !diagnosticAutoDismissDisabled else { return }
        guard !isInteractionHeld,
              (presentation.state == .opening || presentation.state == .visible) else { return }
        let generation = presentationGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation, !self.isInteractionHeld else { return }
            self.close(reason: "idle-timeout")
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.closeDelaySeconds, execute: work)
    }

    func screensChanged() {
        let screen = preferredScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        // The display configuration can change while the pointer is already on a
        // different connected monitor. Re-anchor to the pointer's current screen.
        activeScreen = screen
        let size = presentation.state == .hidden || presentation.state == .closing ? collapsedSize : presentation.size
        let targetFrame = frame(size: size, on: screen)
        applyPanelFrame(targetFrame, display: presentation.state != .hidden)
        if presentation.state == .hidden {
            panel.orderOut(nil)
            panel.ignoresMouseEvents = true
        }
        logPresentation("screens-changed", targetFrame: targetFrame)
    }

    func updateMonitorForPointer() {
        guard let screen = preferredScreen() else { return }
        activeScreen = screen
    }

    private var motionReduced: Bool { presentation.reduceMotion || !preferences.animationsEnabled }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func targetSize(for entryCount: Int, on screen: NSScreen) -> CGSize {
        let count = max(1, min(entryCount, 5))
        let width = tileWidth(for: count, on: screen)
        let horizontalPadding: CGFloat = 18
        let spacing: CGFloat = 7
        let contentHeight: CGFloat = entryCount > 0 ? 117 : 84
        return CGSize(
            width: min(maximumSize.width, CGFloat(count) * width + CGFloat(max(0, count - 1)) * spacing + horizontalPadding * 2),
            height: min(maximumSize.height, contentHeight)
        )
    }

    private func tileWidth(for entryCount: Int, on screen: NSScreen) -> CGFloat {
        let count = CGFloat(max(1, min(entryCount, 5)))
        let spacing = max(0, count - 1) * 7
        let screenWidth = min(maximumSize.width, max(1, screen.visibleFrame.width))
        let availablePerTile = max(42, (screenWidth - 36 - spacing) / count)
        return min(200, availablePerTile)
    }

    private func tileLineCount(for entryCount: Int, on screen: NSScreen) -> Int {
        guard entryCount > 0 else { return 1 }
        let width = tileWidth(for: entryCount, on: screen)
        let charactersPerLine = max(8, Int(width / 5.6))
        return ClipboardHistory.shared.entries.prefix(min(entryCount, 5)).map { entry in
            min(3, entry.displayTitle(maxCharactersPerLine: charactersPerLine, maxLines: 3).components(separatedBy: "\n").count)
        }.max() ?? 1
    }

    private func tileSide(for entryCount: Int, on screen: NSScreen) -> CGFloat {
        min(56, tileWidth(for: entryCount, on: screen))
    }

    private func frame(size: CGSize, on screen: NSScreen) -> NSRect {
        // visibleFrame.maxY is immediately below the menu bar, including notch safe-area handling.
        NSRect(x: screen.visibleFrame.midX - size.width / 2,
               y: screen.visibleFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }

    private func animatePanel(to frame: NSRect, duration: TimeInterval, spring: Bool, completion: (() -> Void)? = nil) {
        guard duration > 0 else {
            applyPanelFrame(frame, display: true)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: spring ? .easeOut : .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            DispatchQueue.main.async { completion?() }
        }
    }

    private func applyPanelFrame(_ frame: NSRect, display: Bool) {
        panel.setFrame(frame, display: display)
        if let host = panel.contentView as? NSHostingView<IslandView> {
            host.frame = NSRect(origin: .zero, size: frame.size)
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
        }
    }

}

private struct IslandView: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var presentation: IslandPresentationModel
    @ObservedObject var preferences: AppPreferences
    let onToggle: () -> Void
    let onSelect: (ClipboardEntry) -> Void
    let onHover: (Bool) -> Void
    let onPointerDown: (Bool) -> Void
    let onDragStarting: (Bool) -> Void
    let onDragChanged: (Bool, NSDragOperation?) -> Void
    let onDragDiagnostic: (String, String) -> Void
    let onResize: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var isExpanded: Bool { presentation.state == .opening || presentation.state == .visible }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: isExpanded ? 25 : 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: isExpanded ? 25 : 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.20), lineWidth: 1)
                }

            if isExpanded {
                VStack(spacing: 4) {
                    if history.entries.isEmpty {
                        Image(systemName: "clipboard")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: presentation.tileSide, height: presentation.tileSide)
                            .help("Appunti vuoti")
                    } else {
                        HStack(alignment: .top, spacing: 7) {
                            ForEach(history.entries.prefix(5)) { entry in
                                ClipboardEntryTile(
                                    entry: entry,
                                    side: presentation.tileSide,
                                    labelWidth: presentation.tileWidth,
                                    labelLineCount: presentation.tileLineCount,
                                    onSelect: { onSelect(entry) },
                                    onPointerDown: onPointerDown,
                                    onDragStarting: onDragStarting,
                                    onDragChanged: onDragChanged,
                                    onDragDiagnostic: onDragDiagnostic,
                                    onHover: onHover
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                Button(action: onToggle) {
                    Capsule()
                        .fill(.white.opacity(0.72))
                        .frame(width: 30, height: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Mostra Isola Clipboard")
                .accessibilityLabel("Mostra Isola Clipboard")
            }
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
        .shadow(color: .black.opacity(isExpanded ? 0.24 : 0.10), radius: isExpanded ? 18 : 5, x: 0, y: isExpanded ? 8 : 1)
        .animation(animation, value: presentation.state)
        .animation(animation, value: presentation.size)
        .preferredColorScheme(preferences.theme.colorScheme)
        .onAppear { presentation.reduceMotion = accessibilityReduceMotion }
        .onChange(of: accessibilityReduceMotion) { _, reduced in presentation.reduceMotion = reduced }
        .onChange(of: history.entries.map(\.id)) { _, _ in onResize(history.entries.count) }
    }

    private var animation: Animation? {
        guard preferences.animationsEnabled, !presentation.reduceMotion, !accessibilityReduceMotion else { return nil }
        return presentation.state == .closing
            ? .easeInOut(duration: 0.20)
            : .spring(response: 0.36, dampingFraction: 0.78, blendDuration: 0.04)
    }
}

private struct ClipboardEntryTile: View {
    let entry: ClipboardEntry
    let side: CGFloat
    let labelWidth: CGFloat
    let labelLineCount: Int
    let onSelect: () -> Void
    let onPointerDown: (Bool) -> Void
    let onDragStarting: (Bool) -> Void
    let onDragChanged: (Bool, NSDragOperation?) -> Void
    let onDragDiagnostic: (String, String) -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if let image = entry.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: entry.symbol)
                        .font(.system(size: side * 0.36, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.84))
                }
            }
            .frame(width: side, height: side)
            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            Text(entry.displayTitle(
                maxCharactersPerLine: max(8, Int(labelWidth / 5.6)),
                maxLines: labelLineCount
            ))
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(labelLineCount)
                .truncationMode(.tail)
                .frame(width: labelWidth, height: CGFloat(labelLineCount) * 13, alignment: .top)
                .foregroundStyle(.primary.opacity(0.82))
        }
        .frame(width: labelWidth)
        .onHover(perform: onHover)
        .overlay(EntryDragSource(entry: entry, onSelect: onSelect, onPointerDown: onPointerDown, onDragStarting: onDragStarting, onDragChanged: onDragChanged, onDragDiagnostic: onDragDiagnostic).onHover(perform: onHover))
        .help(entry.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityHint("Fai clic per ricopiare o trascina verso un’altra app")
    }
}

private struct EntryDragSource: NSViewRepresentable {
    let entry: ClipboardEntry
    let onSelect: () -> Void
    let onPointerDown: (Bool) -> Void
    let onDragStarting: (Bool) -> Void
    let onDragChanged: (Bool, NSDragOperation?) -> Void
    let onDragDiagnostic: (String, String) -> Void

    func makeNSView(context: Context) -> EntryDragNSView {
        let view = EntryDragNSView()
        view.entry = entry
        view.onSelect = onSelect
        view.onPointerDown = onPointerDown
        view.onDragStarting = onDragStarting
        view.onDragChanged = onDragChanged
        view.onDragDiagnostic = onDragDiagnostic
        return view
    }

    func updateNSView(_ view: EntryDragNSView, context: Context) {
        view.entry = entry
        view.onSelect = onSelect
        view.onPointerDown = onPointerDown
        view.onDragStarting = onDragStarting
        view.onDragChanged = onDragChanged
        view.onDragDiagnostic = onDragDiagnostic
    }
}

private final class EntryDragNSView: NSView, NSDraggingSource {
    var entry: ClipboardEntry!
    var onSelect: (() -> Void)?
    var onPointerDown: ((Bool) -> Void)?
    var onDragStarting: ((Bool) -> Void)?
    var onDragChanged: ((Bool, NSDragOperation?) -> Void)?
    var onDragDiagnostic: ((String, String) -> Void)?
    private var mouseDownLocation: NSPoint?
    private var dragStartedForCurrentPress = false

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDragDiagnostic?("tileMouseDown", "content=\(entry.dragContentType) point=\(NSStringFromPoint(event.locationInWindow)) firstMouseAccepted=true")
        guard window != nil else { onSelect?(); return }
        mouseDownLocation = event.locationInWindow
        dragStartedForCurrentPress = false
        onPointerDown?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStartedForCurrentPress,
              let mouseDownLocation,
              hypot(event.locationInWindow.x - mouseDownLocation.x, event.locationInWindow.y - mouseDownLocation.y) > 4 else { return }

        dragStartedForCurrentPress = true
        onDragStarting?(true)
        let item = NSDraggingItem(pasteboardWriter: entry.makePasteboardWriter())
        item.setDraggingFrame(bounds, contents: entry.dragPreview)
        onDragDiagnostic?("dragStartRequested", "content=\(entry.dragContentType) frame=\(NSStringFromRect(bounds))")
        _ = beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = dragStartedForCurrentPress
        mouseDownLocation = nil
        dragStartedForCurrentPress = false
        onDragStarting?(false)
        onPointerDown?(false)
        if !wasDrag { onSelect?() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragChanged?(true, nil)
        onDragDiagnostic?("dragStart", "content=\(entry.dragContentType) screenPoint=\(NSStringFromPoint(screenPoint))")
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onPointerDown?(false)
        onDragChanged?(false, operation)
        onDragDiagnostic?("dragSessionEnded", "content=\(entry.dragContentType) operation=\(operation.rawValue) screenPoint=\(NSStringFromPoint(screenPoint))")
    }
}

private struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var loginSettings: LoginItemSettings
    @ObservedObject var history: ClipboardHistory
    let onPreferencesChanged: () -> Void
    let onCaptureShortcut: (UInt32, UInt32) -> Void
    @State private var isRecordingShortcut = false
    @State private var isConfirmingHistoryClear = false

    var body: some View {
        Form {
            Section("Generale") {
                Toggle("Avvia automaticamente al login", isOn: Binding(
                    get: { loginSettings.isEnabled },
                    set: { loginSettings.setEnabled($0) }
                ))
                if let error = loginSettings.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if loginSettings.needsApproval {
                    Text("Consenti l’avvio in Impostazioni di Sistema → Generali → Elementi di login.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Mostra icona nella barra dei menu", isOn: $preferences.showMenuBarIcon)
                Stepper(value: $preferences.maxItems, in: 1...5) {
                    Text("Elementi conservati: \(preferences.maxItems)")
                }
                .onChange(of: preferences.maxItems) { _, count in history.trim(to: count); onPreferencesChanged() }
            }

            Section("Comportamento") {
                Toggle("Apri l’isola dopo una copia", isOn: $preferences.openAfterCopy)
                Stepper(value: $preferences.closeDelaySeconds, in: 1...10, step: 1) {
                    Text("Chiusura automatica: \(Int(preferences.closeDelaySeconds)) secondi")
                }
                Toggle("Chiudi al clic esterno", isOn: $preferences.closeOnOutsideClick)
                Text("Il timer si sospende mentre il puntatore è sull’isola o durante un trascinamento.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Scorciatoia globale")
                    Spacer()
                    Button(isRecordingShortcut ? "Premi una combinazione…" : AppPreferences.shortcutDescription(keyCode: preferences.shortcutKeyCode, modifiers: preferences.shortcutModifiers)) {
                        isRecordingShortcut = true
                    }
                    .disabled(isRecordingShortcut)
                }
                ShortcutCaptureView(isRecording: $isRecordingShortcut) { keyCode, modifiers in
                    onCaptureShortcut(keyCode, modifiers)
                }
                .frame(width: 0, height: 0)
                Text("⌃⌥, apre Impostazioni anche quando l’icona di menu è nascosta.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Aspetto") {
                Picker("Tema", selection: $preferences.theme) {
                    ForEach(AppTheme.allCases) { theme in Text(theme.title).tag(theme) }
                }
                Toggle("Animazioni", isOn: $preferences.animationsEnabled)
                Label("L’isola resta centrata sotto la barra dei menu del monitor attivo.", systemImage: "display")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Escludi contenuti marcati come riservati", isOn: $preferences.ignoreConcealed)
                Toggle("Escludi contenuti temporanei", isOn: $preferences.ignoreTransient)
                Text("Cronologia solo in memoria; l’app non trasmette dati a servizi cloud.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Svuota cronologia…", role: .destructive) { isConfirmingHistoryClear = true }
            }

            Section("Gesto a tre dita") {
                Text("La scorciatoia globale resta disponibile. La mappatura del trackpad non è inclusa: i rimappatori gratuiti esaminati usano API private e possono richiedere permessi aggiuntivi o confliggere con Mission Control e App Exposé.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .frame(width: 520, height: 700)
        .preferredColorScheme(preferences.theme.colorScheme)
        .alert("Svuotare la cronologia?", isPresented: $isConfirmingHistoryClear) {
            Button("Svuota cronologia", role: .destructive) { history.clear() }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Gli elementi conservati in memoria verranno rimossi.")
        }
        .onChange(of: preferences.showMenuBarIcon) { _, _ in onPreferencesChanged() }
        .onChange(of: preferences.openAfterCopy) { _, _ in onPreferencesChanged() }
        .onChange(of: preferences.closeDelaySeconds) { _, _ in onPreferencesChanged() }
        .onChange(of: preferences.closeOnOutsideClick) { _, _ in onPreferencesChanged() }
        .onChange(of: preferences.theme) { _, _ in onPreferencesChanged() }
        .onChange(of: preferences.animationsEnabled) { _, _ in onPreferencesChanged() }
        .onChange(of: preferences.ignoreConcealed) { _, _ in onPreferencesChanged() }
        .onChange(of: preferences.ignoreTransient) { _, _ in onPreferencesChanged() }
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.isRecording = isRecording
        return view
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onCapture = onCapture
        view.isRecording = isRecording
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((UInt32, UInt32) -> Void)?
    var isRecording = false { didSet { installMonitor() } }
    private var monitor: Any?

    private func installMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard isRecording else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.isRecording = false; return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            guard modifiers != 0 else { return event }
            let code = UInt32(event.keyCode)
            self.onCapture?(code, modifiers)
            self.isRecording = false
            return nil
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
