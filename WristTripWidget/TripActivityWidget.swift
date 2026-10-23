import ActivityKit
import SwiftUI
import UIKit
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
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.train).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityDepartureIndicator(context: context)
                        .font(.caption.weight(.semibold))
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
                PhoneLiveActivityTicketCard(
                    train: context.attributes.train,
                    origin: context.attributes.origin,
                    destination: context.attributes.destination,
                    departureText: departureText,
                    arrivalText: arrivalText,
                    gate: context.state.gate ?? "",
                    waitingRoom: context.state.waitingRoom ?? "",
                    carriage: context.attributes.carriage,
                    seat: context.attributes.seat,
                    departureAt: context.attributes.departureAt,
                    arrivalAt: context.attributes.arrivalAt
                )
                .activityBackgroundTint(Color(uiColor: .systemBackground))
            } else {
                PhoneActivityCard(context: context, departureText: departureText)
                    .activityBackgroundTint(.clear)
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

private struct PhoneLiveActivityTicketCard: View {
    let train: String
    let origin: String
    let destination: String
    let departureText: String
    let arrivalText: String
    let gate: String
    let waitingRoom: String
    let carriage: String
    let seat: String
    let departureAt: Date
    let arrivalAt: Date

    private let gateColor = Color(red: 0.55, green: 0.94, blue: 0.72)
    private let seatColor = Color(red: 1, green: 0.77, blue: 0.4)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            GeometryReader { proxy in
                let width = proxy.size.width.isFinite ? max(1, proxy.size.width) : 1
                let height = proxy.size.height.isFinite ? max(1, proxy.size.height) : 1
                let horizontalPadding = max(10, width * 0.055)
                let contentWidth = max(1, width - horizontalPadding * 2)
                let columnGap = max(5, width * 0.025)
                let onsiteWidth = ActivityOnsiteFieldLayout.columnWidth(containerWidth: width)
                let leftWidth = max(1, contentWidth - onsiteWidth - columnGap)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(display(train, fallback: "待补充"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        seatText
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(width: contentWidth, alignment: .leading)

                    HStack(alignment: .bottom, spacing: columnGap) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(routeTime(at: timeline.date))
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(routeStation(at: timeline.date))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: leftWidth, alignment: .leading)
                        .clipped()

                        VStack(alignment: .trailing, spacing: 0) {
                            if hasActualValue(waitingRoom) {
                                Text(waitingRoom)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: onsiteWidth,
                                           height: ActivityOnsiteFieldLayout.fieldHeight,
                                           alignment: .trailing)
                                    .clipped()
                            }
                            Text(display(gate, fallback: "待公布"))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(gateColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(width: onsiteWidth,
                                       height: ActivityOnsiteFieldLayout.fieldHeight,
                                       alignment: .trailing)
                                .clipped()
                        }
                        .frame(width: onsiteWidth, alignment: .trailing)
                        .clipped()
                    }
                    .frame(width: contentWidth, alignment: .leading)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 6)
                .frame(width: width, height: height, alignment: .topLeading)
            }
            .frame(minHeight: 68)
        }
        .frame(minHeight: 68)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.1, blue: 0.11),
                    in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(at: .now))
    }

    private var seatText: Text {
        Text(display(carriage, fallback: "待补充")).foregroundStyle(.white)
        + Text(" ")
        + Text(display(seat, fallback: "待补充")).foregroundStyle(seatColor)
    }

    private func routeStation(at date: Date) -> String {
        let station = TripScheduleRules.displayedLeg(departure: departureAt, arrival: arrivalAt,
                                                       origin: origin, destination: destination,
                                                       now: date).station
        let value = display(station, fallback: "待补充")
        let characters = Array(value)
        return characters.count > 5 ? "..." + String(characters.suffix(4)) : value
    }

    private func routeTime(at date: Date) -> String {
        display(date >= departureAt && !arrivalText.isEmpty ? arrivalText : departureText,
                fallback: "--:--")
    }

    private func hasActualValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "待公布" && trimmed != "待补充"
    }

    private func display(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func accessibilityText(at date: Date) -> String {
        let waiting = hasActualValue(waitingRoom) ? "，候车室 \(waitingRoom)" : ""
        return "\(display(train, fallback: "待补充"))，\(routeTime(at: date))，\(routeStation(at: date))\(waiting)，检票口 \(display(gate, fallback: "待公布"))，车厢 \(display(carriage, fallback: "待补充"))，座位 \(display(seat, fallback: "待补充"))"
    }
}

private struct ActivityDepartureIndicator: View {
    let context: ActivityViewContext<TripActivityAttributes>
    var color: Color? = nil
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
        .lineLimit(1)
    }

    @ViewBuilder
    private func indicatorContent(at date: Date) -> some View {
        Text(status(at: date))
            .foregroundStyle(color ?? secondaryText)
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
    private let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    private var primaryText: Color {
        .white
    }

    private var secondaryText: Color {
        primaryText.opacity(0.65)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(secondaryText)
                    Text(context.attributes.train)
                        .font(.system(size: 21, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                ActivityDepartureIndicator(context: context, color: primaryText)
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.bottom, 9)

            HStack(alignment: .top, spacing: 7) {
                timeColumn(departureText, context.attributes.origin, alignment: .leading)
                routeMiddle
                timeColumn(arrivalText, context.attributes.destination, alignment: .trailing)
            }
            .padding(.bottom, 12)

            Rectangle()
                .fill(primaryText.opacity(0.18))
                .frame(height: 1)
                .padding(.horizontal, -16)
                .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "chair.fill")
                        .foregroundStyle(secondaryText)
                    Text(seatSummary)
                        .foregroundStyle(primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "door.left.hand.closed")
                        .foregroundStyle(secondaryText)
                    waitingGateContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.bottom, 8)

            Text("以上信息仅供参考，请以车站公告为准。")
                .font(.system(size: 10))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(primaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            cardShape
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(colorScheme == .dark ? 0.35 : 0.45)
                .overlay {
                    cardShape.fill(colorScheme == .dark
                        ? Color.black.opacity(0.02)
                        : Color.black.opacity(0.76))
                }
        }
        .overlay { cardShape.strokeBorder(primaryText.opacity(0.12), lineWidth: 0.75) }
        .clipShape(cardShape)
    }

    private var routeMiddle: some View {
        VStack(spacing: 5) {
            Text(formatted(context.attributes.departureAt, pattern: "M月d日"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
            Capsule()
                .fill(primaryText.opacity(0.82))
                .frame(height: 2)
            Text(durationText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: 76)
        .padding(.top, 3)
    }

    private var arrivalText: String {
        formatted(context.attributes.arrivalAt, pattern: "HH:mm")
    }

    private var durationText: String {
        let minutes = max(0, Int(context.attributes.arrivalAt.timeIntervalSince(context.attributes.departureAt) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(minutes % 60)m"
    }

    private var seatSummary: String {
        "\(display(context.attributes.seatClass)) · \(display(context.attributes.carriage)) \(display(context.attributes.seat))"
    }

    @ViewBuilder
    private var waitingGateContent: some View {
        let waitingRoom = context.state.waitingRoom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gate = context.state.gate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if waitingRoom.isEmpty {
            onsiteField(gate.isEmpty ? "待公布" : gate)
                .frame(height: ActivityOnsiteFieldLayout.fieldHeight)
        } else if gate.isEmpty {
            onsiteField(waitingRoom)
                .frame(height: ActivityOnsiteFieldLayout.fieldHeight)
        } else {
            HStack(alignment: .center, spacing: 4) {
                onsiteField(waitingRoom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("·")
                    .foregroundStyle(secondaryText)
                onsiteField(gate)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: ActivityOnsiteFieldLayout.fieldHeight)
        }
    }

    private func onsiteField(_ original: String) -> some View {
        Text(original)
            .foregroundStyle(primaryText)
            .lineLimit(1)
            .accessibilityLabel(original)
    }

    private func timeColumn(_ time: String, _ station: String,
                            alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(time)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(station)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
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
