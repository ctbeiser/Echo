//
//  solipsistweetsApp.swift
//  solipsistweets
//

import Combine
import SwiftUI

@MainActor
final class SocialAccountStore: ObservableObject {
    private static let configuredTabsKey = "configuredSocialTabs.v1"
    private static let activeTabKey = "activeSocialTab.v1"
    private static let didHandleBlueskyUpgradeKey = "didHandleBlueskyUpgradePrompt.v1"

    @Published private(set) var configuredTabs: [SocialTab]
    @Published var activeTab: SocialTab
    @Published var isPresentingInitialChoice: Bool
    @Published var isPresentingUpgradePrompt: Bool

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let rawConfiguredTabs = userDefaults.stringArray(forKey: Self.configuredTabsKey) ?? []
        var configuredTabs = rawConfiguredTabs.compactMap(SocialTab.init(rawValue:))
        let isExistingInstall = configuredTabs.isEmpty && userDefaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("onScreenSeconds_") }
        if isExistingInstall {
            configuredTabs = [.x]
            userDefaults.set(configuredTabs.map(\.rawValue), forKey: Self.configuredTabsKey)
        }
        let activeTab = SocialTab(rawValue: userDefaults.string(forKey: Self.activeTabKey) ?? "") ?? configuredTabs.first ?? .x

        self.configuredTabs = configuredTabs
        self.activeTab = activeTab
        self.isPresentingInitialChoice = configuredTabs.isEmpty
        self.isPresentingUpgradePrompt = false

        guard !configuredTabs.isEmpty else { return }
        if !configuredTabs.contains(activeTab), let fallback = configuredTabs.first {
            self.activeTab = fallback
            userDefaults.set(fallback.rawValue, forKey: Self.activeTabKey)
        }
        if !configuredTabs.contains(.bluesky), !userDefaults.bool(forKey: Self.didHandleBlueskyUpgradeKey) {
            self.isPresentingUpgradePrompt = true
        }
    }

    var nextTab: SocialTab? {
        guard let currentIndex = configuredTabs.firstIndex(of: activeTab), configuredTabs.count > 1 else { return nil }
        let nextIndex = configuredTabs.index(after: currentIndex)
        return configuredTabs[nextIndex == configuredTabs.endIndex ? configuredTabs.startIndex : nextIndex]
    }

    var missingTabs: [SocialTab] {
        SocialTab.allCases.filter { !configuredTabs.contains($0) }
    }

    func completeInitialChoice(_ tabs: [SocialTab]) {
        let selectedTabs = normalized(tabs)
        configuredTabs = selectedTabs
        activeTab = selectedTabs.first ?? .x
        isPresentingInitialChoice = false
        persistTabs()
        userDefaults.set(activeTab.rawValue, forKey: Self.activeTabKey)
        userDefaults.set(configuredTabs.contains(.bluesky), forKey: Self.didHandleBlueskyUpgradeKey)
    }

    func add(_ tab: SocialTab) {
        guard !configuredTabs.contains(tab) else { return }
        configuredTabs = normalized(configuredTabs + [tab])
        activeTab = tab
        isPresentingInitialChoice = false
        persistTabs()
        userDefaults.set(activeTab.rawValue, forKey: Self.activeTabKey)
        if tab == .bluesky {
            userDefaults.set(true, forKey: Self.didHandleBlueskyUpgradeKey)
            isPresentingUpgradePrompt = false
        }
    }

    func remove(_ tab: SocialTab) {
        guard configuredTabs.count > 1 else { return }
        configuredTabs.removeAll { $0 == tab }
        if activeTab == tab, let fallback = configuredTabs.first {
            activeTab = fallback
            userDefaults.set(fallback.rawValue, forKey: Self.activeTabKey)
        }
        persistTabs()
    }

    func switchToNextTab() {
        guard let currentIndex = configuredTabs.firstIndex(of: activeTab), configuredTabs.count > 1 else { return }
        let nextIndex = configuredTabs.index(after: currentIndex)
        activeTab = configuredTabs[nextIndex == configuredTabs.endIndex ? configuredTabs.startIndex : nextIndex]
        userDefaults.set(activeTab.rawValue, forKey: Self.activeTabKey)
    }

    func declineBlueskyUpgrade() {
        userDefaults.set(true, forKey: Self.didHandleBlueskyUpgradeKey)
        isPresentingUpgradePrompt = false
    }

    func acceptBlueskyUpgrade() {
        add(.bluesky)
        userDefaults.set(true, forKey: Self.didHandleBlueskyUpgradeKey)
        isPresentingUpgradePrompt = false
    }

    private func normalized(_ tabs: [SocialTab]) -> [SocialTab] {
        SocialTab.allCases.filter { tabs.contains($0) }
    }

    private func persistTabs() {
        userDefaults.set(configuredTabs.map(\.rawValue), forKey: Self.configuredTabsKey)
    }
}

@main
struct SolipsistweetsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestedURL: URL
    @StateObject private var screenTimeTracker = OnScreenTimeTracker()
    @StateObject private var accountStore: SocialAccountStore

    init() {
        let accountStore = SocialAccountStore()
        _accountStore = StateObject(wrappedValue: accountStore)
        _requestedURL = State(initialValue: accountStore.activeTab.startURL)
    }

    var body: some Scene {
        WindowGroup {
            SocialWebContainer(requestedURL: $requestedURL)
                .environmentObject(screenTimeTracker)
                .environmentObject(accountStore)
                .onOpenURL { url in
                    guard url.scheme?.lowercased() == "echodotapp" else { return }
                    if let mapped = SocialTab.x.mapEchoDotAppToHTTPS(url) {
                        accountStore.add(.x)
                        accountStore.activeTab = .x
                        requestedURL = mapped
                    }
                }
                .onAppear {
                    updateTracking(for: scenePhase)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            updateTracking(for: newPhase)
        }
    }

    private func updateTracking(for phase: ScenePhase) {
        if phase == .active {
            screenTimeTracker.start()
        } else {
            screenTimeTracker.stopAndFlush()
        }
    }
}

private struct SocialWebContainer: View {
    @Binding var requestedURL: URL
    @EnvironmentObject private var accountStore: SocialAccountStore

    var body: some View {
        Group {
            if accountStore.isPresentingInitialChoice {
                AccountChoiceView(title: "Which accounts would you like to use?", subtitle: "Choose X, Bluesky, or both to get started.") { tabs in
                    accountStore.completeInitialChoice(tabs)
                    requestedURL = accountStore.activeTab.startURL
                }
            } else if !accountStore.activeTab.canonicalHosts.contains(requestedURL.host?.lowercased() ?? "") {
                Color.clear
                    .onAppear {
                        requestedURL = accountStore.activeTab.startURL
                    }
            } else {
                ContentView(
                    requestedURL: $requestedURL,
                    activeTab: accountStore.activeTab,
                    switcherIcon: accountStore.nextTab?.emoji,
                    removableTabs: accountStore.configuredTabs,
                    setupTabs: accountStore.missingTabs,
                    onSwitchTab: {
                        accountStore.switchToNextTab()
                        requestedURL = accountStore.activeTab.startURL
                    },
                    onRemoveTab: { tab in
                        let removedActiveTab = tab == accountStore.activeTab
                        accountStore.remove(tab)
                        if removedActiveTab {
                            requestedURL = accountStore.activeTab.startURL
                        }
                    },
                    onSetupTab: { tab in
                        accountStore.add(tab)
                        requestedURL = accountStore.activeTab.startURL
                    }
                )
                .id(accountStore.activeTab)
                .alert("Bluesky Support Is Here", isPresented: $accountStore.isPresentingUpgradePrompt) {
                    Button("Set Up Bluesky") {
                        accountStore.acceptBlueskyUpgrade()
                        requestedURL = accountStore.activeTab.startURL
                    }
                    Button("Keep Using Twitter / X", role: .cancel) {
                        accountStore.declineBlueskyUpgrade()
                    }
                } message: {
                    Text("Echo can now open Bluesky alongside Twitter / X. Add Bluesky now, or keep your current setup and add it later by shaking your device.")
                }
            }
        }
        .onChange(of: accountStore.activeTab) { _, _ in
            requestedURL = accountStore.activeTab.startURL
        }
    }
}

private struct AccountChoiceView: View {
    let title: String
    let subtitle: String
    let onComplete: ([SocialTab]) -> Void
    @State private var selectedTabs: Set<SocialTab> = [.x]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                ForEach(SocialTab.allCases) { tab in
                    Button {
                        toggle(tab)
                    } label: {
                        HStack(spacing: 12) {
                            Text(tab.emoji)
                                .font(.title3)
                            Text(tab.displayName)
                                .font(.headline)
                            Spacer()
                            Image(systemName: selectedTabs.contains(tab) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedTabs.contains(tab) ? Color.accentColor : Color.secondary)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                onComplete(SocialTab.allCases.filter { selectedTabs.contains($0) })
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(selectedTabs.isEmpty)
            .opacity(selectedTabs.isEmpty ? 0.5 : 1)

            Spacer()
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }

    private func toggle(_ tab: SocialTab) {
        if selectedTabs.contains(tab) {
            guard selectedTabs.count > 1 else { return }
            selectedTabs.remove(tab)
        } else {
            selectedTabs.insert(tab)
        }
    }
}
