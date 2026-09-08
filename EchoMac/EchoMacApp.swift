import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import WebKit

@main
@MainActor
enum EchoMacApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = DesktopAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class DesktopAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = DesktopStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installApplicationMenu()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: DesktopLayout.width, height: DesktopLayout.height)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: DesktopContentView(store: store))
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let image = NSImage(named: "MenuBarBird") else {
            fatalError("Missing required MenuBarBird asset")
        }
        image.isTemplate = true
        let iconHeight: CGFloat = 16
        image.size = NSSize(width: iconHeight * image.size.width / image.size.height, height: iconHeight)
        image.accessibilityDescription = "Echo notifications"
        item.button?.image = image
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let button = item.button {
            button.addSubview(StatusItemDropView(button: button) { [weak self] link in
                guard let self else { return }
                store.open(link.url, in: link.tab)
                showPopover()
            })
        }
        store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }.store(in: &subscriptions)
        updateStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch IncomingURLRouter.route(url) {
            case .openInApp(let mapped, let tab):
                store.open(mapped, in: tab)

            case .openExternal(let external):
                NSWorkspace.shared.open(external)

            case .ignore:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        store.stop()
    }

    func popoverDidShow(_ notification: Notification) {
        store.setPopoverVisible(true)
        store.screenTime.start()
        store.refreshCounts()
        // Start without a preselected control. Tab enters AppKit's normal
        // key-view loop and restores the standard keyboard focus ring.
        popover.contentViewController?.view.containingWindow?.makeFirstResponder(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        store.setPopoverVisible(false)
        store.screenTime.stopAndFlush()
        store.refreshCounts()
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        if popover.isShown { store.screenTime.start() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        store.screenTime.stopAndFlush()
    }

    private func updateStatusItem() {
        statusItem?.button?.title = store.menuBarLabel.isEmpty ? "" : " \(store.menuBarLabel)"
        statusItem?.button?.toolTip = store.statusDescription
        statusItem?.button?.setAccessibilityLabel("Echo. \(store.statusDescription)")
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        // Explicit menu-bar/menu actions and URL drops call this. Launching,
        // reopening, URL-scheme events, and background work never activate it.
        NSApp.activate()
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.containingWindow?.makeKey()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu = quickMenu()
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            store.selectUnreadAccountForOpening()
            showPopover()
        }
    }

    private func quickMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Open Echo", action: #selector(openEcho)))
        menu.addItem(.separator())
        for tab in store.configuredTabs {
            let count = store.statuses[tab]?.count?.label ?? "—"
            let item = menuItem("\(tab.displayName)  \(count)", action: #selector(openAccount(_:)))
            item.representedObject = tab.rawValue
            item.toolTip = store.statuses[tab]?.description
            menu.addItem(item)
        }
        menu.addItem(menuItem("Refresh Counts", action: #selector(refresh)))
        menu.addItem(.separator())
        let login = menuItem("Launch at Login", action: #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Echo", action: #selector(quit), key: "q"))
        return menu
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(menuItem("Open Echo", action: #selector(openEcho), key: "0"))
        app.addItem(.separator())
        app.addItem(menuItem("Quit Echo", action: #selector(quit), key: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = app
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)

        let view = NSMenu(title: "View")
        view.addItem(menuItem("Notifications", action: #selector(notifications), key: "n"))
        view.addItem(menuItem("Reload", action: #selector(reloadPage), key: "r"))
        view.addItem(menuItem("Back", action: #selector(back), key: "["))
        view.addItem(menuItem("Forward", action: #selector(forward), key: "]"))
        view.addItem(menuItem("Switch Account", action: #selector(switchAccount), key: "2"))
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewItem.submenu = view
        main.addItem(viewItem)
        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openEcho() { showPopover() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func refresh() { store.refreshCounts(userInitiated: true) }
    @objc private func reloadPage() { store.activeBrowser?.reload(); refresh() }
    @objc private func back() { store.activeBrowser?.webView.goBack() }
    @objc private func forward() { store.activeBrowser?.webView.goForward() }
    @objc private func switchAccount() { store.switchAccount() }
    @objc private func willSleep() { store.screenTime.stopAndFlush() }
    @objc private func didWake() {
        store.resumeAfterWake()
        if popover.isShown && NSApp.isActive { store.screenTime.start() }
    }

    @objc private func notifications() {
        store.activeBrowser?.load(store.accounts.activeTab.startURL)
        showPopover()
    }

    @objc private func openAccount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = SocialTab(rawValue: raw) else { return }
        store.open(tab.startURL, in: tab)
        showPopover()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            showPopover()
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = "Keep Echo in your Applications folder, then try again. \(error.localizedDescription)"
            if let window = popover.contentViewController?.view.containingWindow { alert.beginSheetModal(for: window) }
        }
    }
}
