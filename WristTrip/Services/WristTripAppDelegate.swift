import UIKit
import OSLog

/// Starts ActivityKit's push-to-start token stream as soon as the iPhone app
/// launches. Live Activity pushes are delivered by iOS directly; the app does
/// not need to stay running for an update to reach the widget.
final class WristTripAppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.clenson.WristTrip", category: "BackgroundRefresh")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // BGTaskScheduler requires registration during launch, before the
        // application finishes launching.
        TripBackgroundRefreshService.register()
        Task { @MainActor in
            ActivityPushTokenService.shared.start()
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Scene callbacks normally arrive through ContentView as well. Keep a
        // delegate-level submission so a suspended scene still leaves the
        // next system refresh request queued.
        Task { @MainActor in
            let store = TripStore()
            let now = Date()
            let changed = store.refreshStatuses(at: now)
            logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) applicationDidEnterBackground now=\(now, privacy: .public) tickets=\(store.tickets.count) statusesChanged=\(changed)")
            TripBackgroundRefreshService.schedule(tickets: store.tickets, now: now)
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Task { @MainActor in
            let store = TripStore()
            let now = Date()
            let changed = store.refreshStatuses(at: now)
            logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) applicationWillEnterForeground now=\(now, privacy: .public) tickets=\(store.tickets.count) statusesChanged=\(changed)")
            TripBackgroundRefreshService.schedule(tickets: store.tickets, now: now)
        }
    }
}
