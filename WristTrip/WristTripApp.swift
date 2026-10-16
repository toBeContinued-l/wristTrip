import SwiftUI

@main
struct WristTripApp: App {
    @UIApplicationDelegateAdaptor(WristTripAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
