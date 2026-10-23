import SwiftUI

@main
struct WristTripApp: App {
    @UIApplicationDelegateAdaptor(WristTripAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WristTripRootView()
        }
    }
}

private struct WristTripRootView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("wristTrip.appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("wristTrip.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var contentReady = false
    @State private var minimumLaunchDurationElapsed = false

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private var launchColorScheme: ColorScheme {
        appearanceMode.colorScheme ?? systemColorScheme
    }

    private var launchComplete: Bool {
        contentReady && minimumLaunchDurationElapsed
    }

    var body: some View {
        ContentView(onReady: { contentReady = true })
            .background(WristTripLaunchView.backgroundColor(for: launchColorScheme).ignoresSafeArea())
            .overlay {
                if !launchComplete {
                    WristTripLaunchView(colorScheme: launchColorScheme) {
                        minimumLaunchDurationElapsed = true
                    }
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                } else if !hasCompletedOnboarding {
                    FirstRunOnboardingView {
                        hasCompletedOnboarding = true
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: launchComplete)
            .preferredColorScheme(appearanceMode.colorScheme)
    }
}
