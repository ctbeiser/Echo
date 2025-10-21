import SwiftUI

@main
struct OrionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestedURL: URL = RedditSiteProfile().startURL
    @StateObject private var screenTimeTracker = OnScreenTimeTracker()
    private let profile: SiteProfile = RedditSiteProfile()

    var body: some Scene {
        WindowGroup {
            ContentView(requestedURL: $requestedURL, profile: profile)
                .environmentObject(screenTimeTracker)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                screenTimeTracker.start()
            } else {
                screenTimeTracker.stopAndFlush()
            }
        }
    }
}
