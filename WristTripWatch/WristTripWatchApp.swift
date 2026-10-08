import SwiftUI

@main
struct WristTripWatchApp: App {
    @StateObject private var store = WatchTicketStore()

    var body: some Scene {
        WindowGroup {
            WatchTripsView(store: store)
        }
    }
}
