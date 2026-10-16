import SwiftUI

/// The compact two-row layout shared by the iPhone preview, Live Activity and watch app.
/// The route changes to the arrival station at the planned departure time so the card
/// remains useful after the train has left without requiring a scrolling label.
struct TrainTicketCard: View {
    let train: String
    let origin: String
    let destination: String
    let departureText: String
    let arrivalText: String
    let gate: String
    let waitingRoom: String
    let carriage: String
    let seat: String
    var departureAt: Date? = nil
    var arrivalAt: Date? = nil

    private let gateColor = Color(red: 0.55, green: 0.94, blue: 0.72)
    private let seatColor = Color(red: 1, green: 0.77, blue: 0.4)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(now: context.date)
        }
        .frame(minHeight: 68)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.1, blue: 0.11), in: RoundedRectangle(cornerRadius: 6))
    }

    private func card(now: Date) -> some View {
        GeometryReader { proxy in
            let horizontalPadding = max(10, proxy.size.width * 0.055)
            let contentWidth = max(0, proxy.size.width - horizontalPadding * 2)
            let gap = max(5, proxy.size.width * 0.025)
            let leftWidth = contentWidth * 0.58
            let rightWidth = contentWidth - leftWidth - gap

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(display(train, fallback: "待补充"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    seatText
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: contentWidth, alignment: .leading)

                HStack(alignment: .bottom, spacing: gap) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(routeTime(now: now))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(routeStation(now: now))
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
                                .minimumScaleFactor(0.65)
                        }
                        Text(display(gate, fallback: "待公布"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(gateColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(width: rightWidth, alignment: .trailing)
                    .clipped()
                }
                .frame(width: contentWidth, alignment: .leading)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(now: now))
    }

    private var seatText: Text {
        let carriageValue = display(carriage, fallback: "待补充")
        let seatValue = display(seat, fallback: "待补充")
        return Text(carriageValue).foregroundStyle(.white)
            + Text(" ")
            + Text(seatValue).foregroundStyle(seatColor)
    }

    private var seatAccessibilityText: String {
        "车厢 \(display(carriage, fallback: "待补充"))，座位 \(display(seat, fallback: "待补充"))"
    }

    private func routeStation(now: Date) -> String {
        let value: String
        if let departureAt, let arrivalAt {
            value = TripScheduleRules.displayedLeg(departure: departureAt, arrival: arrivalAt,
                                                   origin: origin, destination: destination,
                                                   now: now).station
        } else {
            value = origin
        }
        return compactStation(display(value, fallback: "待补充"))
    }

    private func routeTime(now: Date) -> String {
        if let departureAt, let arrivalAt {
            return display(now >= departureAt && !arrivalText.isEmpty ? arrivalText : departureText,
                           fallback: "--:--")
        }
        return display(departureText, fallback: "--:--")
    }

    private func compactStation(_ value: String) -> String {
        let characters = Array(value)
        guard characters.count > 5 else { return value }
        return "..." + String(characters.suffix(4))
    }

    private func hasActualValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "待公布" && trimmed != "待补充"
    }

    private func accessibilityText(now: Date) -> String {
        let waitingRoomText = hasActualValue(waitingRoom) ? "，候车室 \(waitingRoom)" : ""
        return "\(display(train, fallback: "待补充"))，\(routeTime(now: now))，\(routeStation(now: now))\(waitingRoomText)，检票口 \(display(gate, fallback: "待公布"))，\(seatAccessibilityText)"
    }

    private func display(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
