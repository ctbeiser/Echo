//
//  solipsistweetsApp.swift
//  solipsistweets
//

import Combine
import SwiftUI
import UIKit

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
                    switch IncomingURLRouter.route(url) {
                    case .openInApp(let mapped, let tab):
                        accountStore.add(tab)
                        accountStore.select(tab)
                        requestedURL = mapped

                    case .openExternal(let externalURL):
                        UIApplication.shared.open(externalURL, options: [:], completionHandler: nil)

                    case .ignore:
                        break
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
            } else if !accountStore.activeTab.hasCanonicalHost(for: requestedURL) {
                Color.clear
                    .onAppear {
                        requestedURL = accountStore.activeTab.startURL
                    }
            } else {
                ContentView(
                    requestedURL: $requestedURL,
                    activeTab: accountStore.activeTab,
                    nextTab: accountStore.nextTab,
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
                    },
                    onOpenURLInTab: { url, tab in
                        accountStore.add(tab)
                        accountStore.select(tab)
                        requestedURL = url
                    }
                )
                .alert("Bluesky Support Is Here", isPresented: $accountStore.isPresentingUpgradePrompt) {
                    Button("Set Up Bluesky") {
                        accountStore.acceptBlueskyUpgrade()
                        requestedURL = accountStore.activeTab.startURL
                    }
                    Button("Keep Using Twitter", role: .cancel) {
                        accountStore.declineBlueskyUpgrade()
                    }
                } message: {
                    Text("Echo can now open Bluesky alongside Twitter. Add Bluesky now, or keep your current setup and add it later by shaking your device.")
                }
            }
        }
        .onChange(of: accountStore.activeTab) { _, _ in
            guard !accountStore.activeTab.hasCanonicalHost(for: requestedURL) else { return }
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
