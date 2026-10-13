import SwiftUI

@main
struct WristTripApp: App {
    @UIApplicationDelegateAdaptor(WristTripAppDelegate.self) private var appDelegate
    @State private var contentReady = false
    @State private var minimumLaunchDurationElapsed = false

    init() {
        TripBackgroundRefreshService.register()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView {
                    withAnimation(.easeOut(duration: 0.25)) {
                        contentReady = true
                    }
                }
                if !contentReady || !minimumLaunchDurationElapsed {
                    WristTripLaunchView {
                        withAnimation(.easeOut(duration: 0.2)) {
                            minimumLaunchDurationElapsed = true
                        }
                    }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
    }
}
