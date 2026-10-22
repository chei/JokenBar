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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    static let refreshInterval: TimeInterval = 10 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let popoverView = PopoverView { [weak self] in
            self?.makeMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        let hosting = NSHostingController(rootView: popoverView.environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient

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
        } else {
            Task { await model.refreshAll() }
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // Attaching the menu only for this click keeps left-click for the popover.
            popover.performClose(nil)
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { await model.refreshIfStale() }
        }
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

    // MARK: Menu (gear button and right-click)

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Add Account…", #selector(addAccount)))
        menu.addItem(.separator())
        menu.addItem(item("Launch at Login", #selector(toggleLaunchAtLogin), on: model.launchAtLogin))
        menu.addItem(item("Global Shortcut ⌃⌥J", #selector(toggleHotKey), on: model.hotKeyEnabled))
        menu.addItem(.separator())
        menu.addItem(item("Quit JokenBar", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func addAccount() { model.login() }
    @objc private func toggleLaunchAtLogin() { model.launchAtLogin.toggle() }
    @objc private func toggleHotKey() { model.hotKeyEnabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

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
