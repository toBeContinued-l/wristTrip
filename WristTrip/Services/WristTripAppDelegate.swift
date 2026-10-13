import UIKit

/// Starts ActivityKit's push-to-start token stream as soon as the iPhone app
/// launches. Live Activity pushes are delivered by iOS directly; the app does
/// not need to stay running for an update to reach the widget.
final class WristTripAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in
            ActivityPushTokenService.shared.start()
        }
        return true
    }
}
