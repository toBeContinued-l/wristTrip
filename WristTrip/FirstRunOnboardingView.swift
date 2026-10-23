import SwiftUI

struct FirstRunOnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var step = 0

    private let imageNames = ["OnboardingStep1", "OnboardingStep2", "OnboardingStep3"]
    private let accent = Color.indigo

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom
            let cardHeight = max(240, availableHeight - 156)
            let cardWidth = min(geometry.size.width - 40, cardHeight * 768 / 1376)

            VStack(spacing: 0) {
                Spacer(minLength: 4)

                Image(imageNames[step])
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardWidth, height: cardWidth * 1376 / 768)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.12), radius: 24, x: 0, y: 12)
                    .accessibilityLabel("第 \(step + 1) 步操作说明")
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                if value.translation.width < -40, step < imageNames.count - 1 {
                                    step += 1
                                } else if value.translation.width > 40, step > 0 {
                                    step -= 1
                                }
                            }
                    )

                HStack(spacing: 8) {
                    ForEach(imageNames.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? accent : Color.primary.opacity(0.20))
                            .frame(width: index == step ? 28 : 7, height: 7)
                    }
                }
                .padding(.top, 23)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("第 \(step + 1) 步，共 3 步")

                HStack(spacing: 0) {
                    HStack(spacing: 16) {
                        if step > 0 {
                            Button { step -= 1 } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 32, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("上一步")
                        }

                        Button("跳过", action: onFinish)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 48)
                    }

                    Spacer()

                    Button {
                        if step == imageNames.count - 1 {
                            onFinish()
                        } else {
                            step += 1
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Text(step == imageNames.count - 1 ? "开始使用" : "继续")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: step == imageNames.count - 1 ? "checkmark" : "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 23)
                        .frame(height: 52)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.48 : 0.30), lineWidth: 0.8)
                                .shadow(color: accent.opacity(0.30), radius: 7)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(onboardingBackground.ignoresSafeArea())
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var onboardingBackground: Color {
        Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemGroupedBackground)
    }
}
