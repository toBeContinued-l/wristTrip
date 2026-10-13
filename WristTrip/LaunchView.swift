import SwiftUI

/// A short in-app handoff screen that keeps first launch legible while the local
/// ticket store and activity services finish attaching to the scene.
struct WristTripLaunchView: View {
    let onMinimumDurationElapsed: () -> Void

    init(onMinimumDurationElapsed: @escaping () -> Void = {}) {
        self.onMinimumDurationElapsed = onMinimumDurationElapsed
    }

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.10)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                routeMark

                VStack(spacing: 7) {
                    Text("腕上车次")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("下一站，抬腕就知道")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }

                ProgressView()
                    .tint(Color(red: 0.55, green: 0.94, blue: 0.72))
                    .padding(.top, 8)
            }
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("腕上车次，正在准备行程")
        .task {
            // Keep the handoff visible long enough to be perceived on a real device.
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            onMinimumDurationElapsed()
        }
    }

    private var routeMark: some View {
        HStack(spacing: 0) {
            stationDot
            Rectangle()
                .fill(Color(red: 0.55, green: 0.94, blue: 0.72))
                .frame(width: 74, height: 2)
            Image(systemName: "tram.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.77, blue: 0.4))
                .frame(width: 38, height: 38)
            Rectangle()
                .fill(Color(red: 0.55, green: 0.94, blue: 0.72))
                .frame(width: 74, height: 2)
            stationDot
        }
    }

    private var stationDot: some View {
        Circle()
            .fill(Color(red: 0.55, green: 0.94, blue: 0.72))
            .frame(width: 10, height: 10)
    }
}
