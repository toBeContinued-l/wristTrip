import SwiftUI

struct WatchPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket
    let onSync: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TrainTicketCard(train: ticket.train, origin: ticket.from, destination: ticket.to,
                                departureText: departureText, arrivalText: arrivalText,
                                gate: ticket.gate, waitingRoom: ticket.waitingRoom,
                                carriage: ticket.carriage, seat: ticket.seat,
                                departureAt: ticket.plannedDepartureAt,
                                arrivalAt: ticket.plannedArrivalAt)
                    .frame(width: 184)
                    .frame(maxWidth: .infinity)

                Text("车票详情")
                    .font(.headline)
                    .padding(.top, 6)
                TicketSummaryPanel(ticket: ticket)
                TicketOnsitePanel(ticket: ticket)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onSync) {
                Label("显示到智能叠放", systemImage: "applewatch.and.arrow.forward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .background(TripPalette.page(for: colorScheme).ignoresSafeArea())
        .navigationTitle("智能叠放预览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var departureText: String {
        guard let date = ticket.plannedDepartureAt else { return ticket.departTime }
        return formatted(date, pattern: "HH:mm")
    }

    private var arrivalText: String {
        guard let date = ticket.plannedArrivalAt else { return ticket.arriveTime }
        return formatted(date, pattern: "HH:mm")
    }

    private func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = ticket.displayTimezone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

}
