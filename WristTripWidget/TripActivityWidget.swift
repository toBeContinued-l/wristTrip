import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TripWidgetBundle: WidgetBundle {
    var body: some Widget {
        TripActivityWidget()
    }
}

struct TripActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripActivityCard(context: context)
                .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.train).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.plannedStatus).font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.origin) → \(context.attributes.destination)")
                        .lineLimit(1)
                }
            } compactLeading: {
                Text(context.attributes.train).font(.caption.bold())
            } compactTrailing: {
                Text(context.attributes.departureAt, style: .time).font(.caption2)
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

private struct TripActivityCard: View {
    let context: ActivityViewContext<TripActivityAttributes>
    @Environment(\.activityFamily) private var family

    private var departureText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: context.attributes.timezoneIdentifier)
            ?? TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: context.attributes.departureAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(context.attributes.train).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Text(context.state.plannedStatus).font(.caption2).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text(context.attributes.origin).lineLimit(1)
                Image(systemName: "arrow.right")
                Text(context.attributes.destination).lineLimit(1)
            }
            .font(.subheadline)
            if let demoExpiresAt = context.attributes.demoExpiresAt {
                Text("演示至 \(demoExpiresAt, style: .time)").font(.caption).lineLimit(1)
            } else {
                Text("计划 \(departureText)").font(.caption).lineLimit(1)
            }
            if !context.attributes.fare.isEmpty {
                Text("票价 \(context.attributes.fare)").font(.caption2).lineLimit(1)
            }
            if family == .small {
                Text("\(display(context.attributes.carriage)) · \(display(context.attributes.seat)) · \(display(context.attributes.seatClass))")
                    .font(.caption2).lineLimit(1)
            }
        }
        .padding(10)
    }

    private func display(_ value: String) -> String {
        value.isEmpty ? "待补充" : value
    }
}
