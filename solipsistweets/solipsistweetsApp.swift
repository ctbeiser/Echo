//
//  solipsistweetsApp.swift
//  solipsistweets
//

import SwiftUI

@main
struct solipsistweetsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestedURL: URL = XSiteProfile().startURL
    @StateObject private var screenTimeTracker = OnScreenTimeTracker()
    private let profile: SiteProfile = XSiteProfile()

    var body: some Scene {
        WindowGroup {
            ContentView(requestedURL: $requestedURL, profile: profile)
                .environmentObject(screenTimeTracker)
                .onOpenURL { url in
                    guard url.scheme?.lowercased() == "echodotapp" else { return }
                    if let mapped = profile.mapEchoDotAppToHTTPS(url) {
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
