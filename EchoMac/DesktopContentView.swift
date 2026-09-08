import AppKit
import SwiftUI
import WebKit

struct DesktopContentView: View {
    @ObservedObject var store: DesktopStore
    @State private var selectedTabs: Set<SocialTab> = [.x]

    var body: some View {
        Group {
            if store.accounts.isPresentingInitialChoice {
                setupView
            } else {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    DesktopPagesView(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: DesktopLayout.width, height: DesktopLayout.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                store.activeBrowser?.webView.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Back (⌘[)")
            .accessibilityLabel("Back")
            .frame(width: 24)

            Spacer(minLength: 0)

            DesktopAccountSwitcher(store: store)

            Spacer(minLength: 0)

            Menu {
                ForEach(store.accounts.missingTabs) { tab in
                    Button(tab.setupTitle) { store.add(tab) }
                }
                if store.configuredTabs.count > 1 {
                    ForEach(store.configuredTabs) { tab in
                        Button("Remove \(tab.displayName)") { store.remove(tab) }
                    }
                }
                Divider()
                Button("Refresh Notification Counts") { store.refreshCounts(userInitiated: true) }
                Button("Quit Echo") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(width: 24)
            .help("Accounts and app actions")
            .accessibilityLabel("Accounts and app actions")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var setupView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Echo for Mac")
                    .font(.largeTitle.weight(.semibold))
                Text("Your notifications, a little closer.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("Choose your accounts, then sign in. Echo keeps your unread count in the menu bar, even after you close this popover.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                ForEach(DesktopStore.tabOrder) { tab in
                    Toggle(isOn: Binding(
                        get: { selectedTabs.contains(tab) },
                        set: { enabled in
                            if enabled { selectedTabs.insert(tab) } else { selectedTabs.remove(tab) }
                        }
                    )) {
                        Text("\(tab.emoji)  \(tab.displayName)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Button("Continue") {
                store.configure(DesktopStore.tabOrder.filter { selectedTabs.contains($0) })
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedTabs.isEmpty)
            Text("Click Echo’s menu bar icon to return. Right-click it for quick actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DesktopAccountSwitcher: View {
    @ObservedObject var store: DesktopStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tabWidth: CGFloat = 112
    private static let tabHeight: CGFloat = 28
    private static let inset: CGFloat = 3

    private var selectionPosition: CGFloat {
        let lastIndex = CGFloat(max(0, store.configuredTabs.count - 1))
        return min(max(CGFloat(store.activePageIndex) - store.swipeProgress, 0), lastIndex)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.primary.opacity(colorScheme == .dark ? 0.40 : 0.28))
                .frame(width: Self.tabWidth, height: Self.tabHeight)
                .offset(x: Self.inset + selectionPosition * Self.tabWidth)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                ForEach(store.configuredTabs) { tab in
                    let selected = store.accounts.activeTab == tab
                    Button {
                        store.select(tab)
                    } label: {
                        Text(store.switcherLabel(for: tab))
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(width: Self.tabWidth, height: Self.tabHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(tab.displayName)
                    .accessibilityValue(store.statuses[tab]?.description ?? "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("accountSwitcher.\(tab.rawValue)")
                }
            }
            .padding(Self.inset)
            .transaction { $0.animation = nil }
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .fixedSize()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: store.accounts.activeTab)
        .transaction { if reduceMotion { $0.animation = nil } }
        .onMoveCommand { direction in
            switch direction {
            case .left: store.switchAccount(.previous)
            case .right: store.switchAccount(.next)
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accounts")
    }
}
