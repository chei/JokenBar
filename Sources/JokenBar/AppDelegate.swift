import AppKit
import Carbon.HIToolbox
import Combine
import QuotaCore
import SwiftUI

@main
@MainActor
enum JokenBarMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // no Dock icon
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var revealTimer: Timer?
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    static let refreshInterval: TimeInterval = 10 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        let popoverView = PopoverView { [weak self] in self?.toggleSettings() }
        let hosting = NSHostingController(rootView: popoverView.environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        model.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                    self?.updateHotKey()
                }
            }
            .store(in: &cancellables)
        updateHotKey()

        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refreshAll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.model.refreshAll() }
        }

        updateStatusItem()
        if model.accounts.isEmpty {
            DispatchQueue.main.async { self.togglePopover() }
        }
        Task {
            await model.removeOrphanedDataStores()
            await model.refreshAll()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // With keyboard navigation on, AppKit focuses the first button right away;
            // start unfocused so the focus ring only shows once the user presses Tab.
            DispatchQueue.main.async { self.popover.contentViewController?.view.window?.makeFirstResponder(nil) }
            Task { await model.refreshIfStale() }
        }
    }

    /// Animates the settings section by stepping its revealed height; the popover
    /// resizes with every step (its own resize animation is off meanwhile).
    private func toggleSettings() {
        model.settingsExpanded.toggle()
        let start = model.settingsReveal
        let target: CGFloat = model.settingsExpanded ? 1 : 0
        let duration = 0.25 * abs(target - start)
        let began = CACurrentMediaTime()
        popover.animates = false
        revealTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let t = duration > 0 ? min((CACurrentMediaTime() - began) / duration, 1) : 1
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                self.model.settingsReveal = start + (target - start) * eased
                if t >= 1 {
                    timer.invalidate()
                    self.popover.animates = true
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }

    func popoverDidClose(_ notification: Notification) {
        revealTimer?.invalidate()
        popover.animates = true
        model.settingsExpanded = false
        model.settingsReveal = 0
    }

    private func updateHotKey() {
        if !model.hotKeyEnabled {
            hotKey = nil
        } else if hotKey == nil {
            // ⌃⌥J: a plain ⌘ shortcut would be stolen from every other app.
            hotKey = HotKey(keyCode: kVK_ANSI_J, modifiers: controlKey | optionKey) { [weak self] in
                DispatchQueue.main.async { self?.togglePopover() }
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let headline = model.menuBarSnapshot?.headline() ?? .unknown

        let symbol: String
        switch headline {
        case .included: symbol = "gift.fill"
        case .monthly: symbol = "dollarsign.circle.fill"
        case .percent: symbol = "gauge.with.dots.needle.33percent"
        case .unknown: symbol = "questionmark.circle"
        }
        let color = headline.level?.color ?? .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Claude usage")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false

        button.image = image
        button.imagePosition = .imageLeading
        button.title = headline != .unknown ? " " + headline.shortText : ""
        button.toolTip = model.hotKeyEnabled ? "JokenBar – ⌃⌥J" : "JokenBar"
    }
}

extension Level {
    var color: NSColor {
        switch self {
        case .ok: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}
