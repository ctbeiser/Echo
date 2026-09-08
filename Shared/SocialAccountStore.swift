import Combine
import Foundation

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
        if rawConfiguredTabs.isEmpty == false,
           configuredTabs.contains(.bluesky) == false,
           userDefaults.object(forKey: Self.didHandleBlueskyUpgradeKey) != nil,
           userDefaults.bool(forKey: Self.didHandleBlueskyUpgradeKey) == false {
            userDefaults.set(true, forKey: Self.didHandleBlueskyUpgradeKey)
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
        userDefaults.set(true, forKey: Self.didHandleBlueskyUpgradeKey)
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

    func select(_ tab: SocialTab) {
        guard configuredTabs.contains(tab) else { return }
        activeTab = tab
        userDefaults.set(tab.rawValue, forKey: Self.activeTabKey)
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
