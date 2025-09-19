//
//  solipsistweetsApp.swift
//  solipsistweets
//
//  Created by Chris Beiser on 8/31/25.
//

import SwiftUI
import UIKit

@main
struct solipsistweetsApp: App {
    @State private var requestedURL: URL = URL(string: "https://x.com/notifications")!
    var body: some Scene {
        WindowGroup {
            ContentView(requestedURL: $requestedURL)
                .onOpenURL { url in
                    guard url.scheme?.lowercased() == "echodotapp" else { return }
                    if let mapped = Coordinator.mapEchoDotAppToHTTPS(url: url) {
                        requestedURL = mapped
                    }
                }
        }
    }
}
