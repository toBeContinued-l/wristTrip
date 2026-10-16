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
                .activityBackgroundTint(Color(uiColor: .systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.train).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityDepartureIndicator(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.origin) → \(context.attributes.destination)")
                        .lineLimit(1)
                }
            } compactLeading: {
                Text(context.attributes.train).font(.caption.bold())
            } compactTrailing: {
                ActivityRouteTimeIndicator(context: context)
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

private struct ActivityRouteTimeIndicator: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        // Keep the compact phone presentation tied to the planned departure.
        // The status text may change elsewhere, but this route summary does
        // not switch to the arrival time after departure.
        Text(context.attributes.departureAt, style: .time)
            .font(.caption2)
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
        Group {
            if family == .small {
                TrainTicketCard(
                    train: context.attributes.train, origin: context.attributes.origin,
                    destination: context.attributes.destination,
                    departureText: departureText, arrivalText: arrivalText,
                    gate: context.state.gate ?? "", waitingRoom: context.state.waitingRoom ?? "",
                    carriage: context.attributes.carriage, seat: context.attributes.seat,
                    departureAt: context.attributes.departureAt,
                    arrivalAt: context.attributes.arrivalAt
                )
            } else {
                PhoneActivityCard(context: context, departureText: departureText)
            }
        }
    }

    private var arrivalText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: context.attributes.timezoneIdentifier)
            ?? TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: context.attributes.arrivalAt)
    }
}

private struct ActivityDepartureIndicator: View {
    let context: ActivityViewContext<TripActivityAttributes>
    @Environment(\.colorScheme) private var colorScheme

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        primaryText.opacity(0.62)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            indicatorContent(at: timeline.date)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }

    @ViewBuilder
    private func indicatorContent(at date: Date) -> some View {
        Text(status(at: date))
            .foregroundStyle(secondaryText)
    }

    private func status(at date: Date) -> String {
        // When ActivityKit marks the content stale at planned arrival, keep
        // the visible status honest until the app can perform the final end.
        if context.isStale { return TripScheduleStatus.arrived.rawValue }
        return TripScheduleRules.status(departure: context.attributes.departureAt,
                                        arrival: context.attributes.arrivalAt,
                                        now: date).rawValue
    }
}

private struct PhoneActivityCard: View {
    let context: ActivityViewContext<TripActivityAttributes>
    let departureText: String
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.25, green: 0.86, blue: 1.0)
            : Color(red: 0.0, green: 0.42, blue: 0.72)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        primaryText.opacity(0.62)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tram.fill")
                        .foregroundStyle(accent)
                    Text(context.attributes.train)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                ActivityDepartureIndicator(context: context)
                    .frame(width: 72, alignment: .trailing)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // The iPhone activity is a ticket summary. Its planned
                // route is fixed for the whole activity lifetime; the
                // status label may change, but the left and right legs
                // must remain origin/departure and destination/arrival.
                timeColumn(departureText, context.attributes.origin, alignment: .leading)
                routeMiddle
                timeColumn(arrivalText, context.attributes.destination, alignment: .trailing)
            }

            Divider()
                .overlay(primaryText.opacity(0.22))

            HStack(spacing: 8) {
                Text(waitingGateSummary)
                    .fontWeight(.semibold)
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    Image(systemName: "person.crop.rectangle")
                    Text("\(display(context.attributes.seatClass)) · \(display(context.attributes.carriage)) \(display(context.attributes.seat))")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2)

            Text("以上信息仅供参考，请以车站公告为准。")
                .font(.caption2)
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(primaryText)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var routeMiddle: some View {
        VStack(spacing: 0) {
            Text(formatted(context.attributes.departureAt, pattern: "M月d日"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accent)
                    .frame(height: 2)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 58)
            Text(durationText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: 62)
    }

    private var arrivalText: String {
        formatted(context.attributes.arrivalAt, pattern: "HH:mm")
    }

    private var durationText: String {
        let minutes = max(0, Int(context.attributes.arrivalAt.timeIntervalSince(context.attributes.departureAt) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(minutes % 60)m"
    }

    private var waitingGateSummary: String {
        let waitingRoom = context.state.waitingRoom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gate = context.state.gate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (waitingRoom.isEmpty, gate.isEmpty) {
        case (false, false): return "\(waitingRoom) · \(gate)"
        case (false, true): return waitingRoom
        case (true, false): return gate
        default: return "待公布"
        }
    }

    private func timeColumn(_ time: String, _ station: String,
                            alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(time).font(.headline.weight(.bold)).monospacedDigit().foregroundStyle(primaryText)
            Text(station).font(.caption2.weight(.medium)).foregroundStyle(primaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: context.attributes.timezoneIdentifier)
            ?? TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private func display(_ value: String, fallback: String = "待补充") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
