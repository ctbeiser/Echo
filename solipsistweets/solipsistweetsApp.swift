//
//  solipsistweetsApp.swift
//  solipsistweets
//

import SwiftUI
import UIKit
import Combine

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
                    if scenePhase == .active {
                        screenTimeTracker.start()
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                screenTimeTracker.start()
            } else {
                screenTimeTracker.stopAndFlush()
            }
        }
    }
}

