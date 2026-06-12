import AppKit
import ClowderKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    private var frames: [NSImage] = []
    private var sequencer = FrameSequencer(frameCount: CharacterRenderer.frameCount)
    // nonisolated(unsafe) lets the nonisolated deinit reach the timer; all writes stay on MainActor.
    nonisolated(unsafe) private var animationTimer: Timer?
    nonisolated(unsafe) private var occlusionObserver: (any NSObjectProtocol)?
    private var observationTask: Task<Void, Never>?

    // The controller lives for the app's lifetime; this guards teardown scenarios.
    deinit {
        observationTask?.cancel()
        animationTimer?.invalidate()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        loadCharacter(environment.config.general.character)
        if let button = statusItem.button {
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PanelView(environment: environment))

        // Re-tune animation speed and refresh modules whenever a snapshot lands.
        observationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.observeSnapshotOnce()
            }
        }

        // The status item's window is occluded when the menu bar is hidden
        // (full-screen apps, screen lock); stop burning timer wakeups then.
        if let window = statusItem.button?.window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.retimeAnimation() }
            }
        }
    }

    private func observeSnapshotOnce() async {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = environment.store.snapshot.date
            } onChange: {
                Task { @MainActor in continuation.resume() }
            }
        }
        environment.refreshModules()
        retimeAnimation()
    }

    func loadCharacter(_ character: RunnerCharacter) {
        frames = CharacterRenderer.frames(for: character)
        sequencer = FrameSequencer(frameCount: frames.count)
        statusItem.button?.image = frames.first
        retimeAnimation()
    }

    private func retimeAnimation() {
        let visible = statusItem.button?.window?.occlusionState.contains(.visible) ?? true
        guard visible else {
            animationTimer?.invalidate()
            animationTimer = nil
            return
        }
        let load = environment.store.snapshot.cpu?.totalLoad ?? 0
        let interval = FrameSequencer.interval(forLoad: load)
        if let timer = animationTimer,
           abs(timer.timeInterval - interval) <= 0.01 { return }
        animationTimer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        RunLoop.main.add(t, forMode: .common)
        animationTimer = t
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        sequencer.advance()
        statusItem.button?.image = frames[sequencer.index]
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()
        let awakeOn = environment.keepAwake.engine.state != .off
        menu.addItem(withTitle: awakeOn ? "Turn Keep Awake Off" : "Keep Awake",
                     action: #selector(toggleKeepAwake), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Clowder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // detach so left-click keeps opening the popover
    }

    @objc private func toggleKeepAwake() {
        let engine = environment.keepAwake.engine
        engine.state == .off ? engine.enable(for: nil) : engine.disable()
    }

    @objc private func openSettings() {
        SettingsOpener.shared.open()
    }
}
