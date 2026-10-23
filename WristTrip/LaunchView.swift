import SwiftUI

struct WristTripLaunchView: View {
    let colorScheme: ColorScheme
    let onMinimumDurationElapsed: () -> Void

    init(colorScheme: ColorScheme, onMinimumDurationElapsed: @escaping () -> Void = {}) {
        self.colorScheme = colorScheme
        self.onMinimumDurationElapsed = onMinimumDurationElapsed
    }

    private static func traits(for colorScheme: ColorScheme) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    }

    static func backgroundColor(for colorScheme: ColorScheme) -> Color {
        let traits = traits(for: colorScheme)
        let color = UIColor(named: "LaunchBackground") ?? .systemBackground
        return Color(uiColor: color.resolvedColor(with: traits))
    }

    private var textColor: Color {
        Color(uiColor: UIColor.label.resolvedColor(with: Self.traits(for: colorScheme)))
    }

    var body: some View {
        ZStack {
            Self.backgroundColor(for: colorScheme)

            VStack(spacing: 18) {
                Image("LaunchLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 78, height: 78)

                Text("下一站，抬腕就知道")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(textColor)
                    .fixedSize()
            }
            .offset(y: -24)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("下一站，抬腕就知道")
        .task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            onMinimumDurationElapsed()
        }
    }
}
