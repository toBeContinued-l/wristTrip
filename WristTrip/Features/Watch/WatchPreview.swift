import SwiftUI

struct WatchPreview: View {
    let ticket: Ticket
    let onSync: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(ticket.train).font(.title2.bold())
                        Spacer()
                        Text(ticket.status.rawValue).font(.caption.weight(.semibold))
                    }
                    Text("\(ticket.from) → \(ticket.to)")
                        .font(.headline)
                        .lineLimit(2)
                    Text("计划 \(ticket.date) \(ticket.departTime)")
                        .font(.subheadline)
                    Text("\(display(ticket.carriage)) · \(display(ticket.seat))")
                        .font(.subheadline.weight(.semibold))
                    if !ticket.seatClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(ticket.seatClass).font(.caption)
                    }
                    if !ticket.fare.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("票价 \(ticket.fare)").font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: 210, alignment: .leading)
                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text("车票详情").font(.headline)
                    detail("席别", display(ticket.seatClass))
                    detail("候车室", display(ticket.waitingRoom, fallback: "待公布"))
                    detail("检票口", display(ticket.gate, fallback: "待公布"))
                }
                Button(action: onSync) {
                    Label("显示到智能叠放", systemImage: "applewatch.and.arrow.forward")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .navigationTitle("智能叠放预览")
    }

    private func display(_ value: String, fallback: String = "待补充") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
