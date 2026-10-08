import SwiftUI

private enum WatchDateText {
    static func format(_ date: Date, timezone: TimeZone, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timezone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

struct WatchTripsView: View {
    @ObservedObject var store: WatchTicketStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let current = store.currentTicket(at: context.date)
            let upcoming = store.sortedTickets.filter { $0.id != current?.id && $0.status(at: context.date) != "已到站" }
            let history = store.sortedTickets.filter { $0.status(at: context.date) == "已到站" }.reversed()
            NavigationStack {
                List {
                    if let current {
                        Section(current.departureAt <= context.date ? "当前车次" : "下一趟") {
                            NavigationLink {
                                WatchTicketDetailView(ticket: current)
                            } label: {
                                WatchTicketRow(ticket: current, now: context.date)
                            }
                        }
                    }

                    if !upcoming.isEmpty {
                        Section("接下来的车次") {
                            ForEach(upcoming) { ticket in
                                NavigationLink {
                                    WatchTicketDetailView(ticket: ticket)
                                } label: {
                                    WatchTicketRow(ticket: ticket, now: context.date)
                                }
                            }
                        }
                    }

                    if !history.isEmpty {
                        Section("历史车票") {
                            ForEach(history) { ticket in
                                NavigationLink {
                                    WatchTicketDetailView(ticket: ticket)
                                } label: {
                                    WatchTicketRow(ticket: ticket, now: context.date)
                                }
                            }
                        }
                    }

                    if store.snapshot == nil || store.sortedTickets.isEmpty {
                        ContentUnavailableView("暂无车票", systemImage: "ticket", description: Text("在 iPhone 上确认车票并同步"))
                    }

                    if let syncedAt = store.snapshot?.generatedAt {
                        Text("离线数据 · 同步于 \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    if let syncError = store.syncError {
                        Text(syncError).font(.caption2).foregroundStyle(.orange)
                    }
                }
                .navigationTitle("抬腕车次")
            }
        }
    }
}

private struct WatchTicketRow: View {
    let ticket: WatchTicket
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(ticket.train).font(.headline)
                Spacer(minLength: 3)
                Text(ticket.status(at: now)).font(.caption2).foregroundStyle(.green)
            }
            Text("\(ticket.origin) → \(ticket.destination)")
                .font(.subheadline)
                .lineLimit(2)
            Text("计划 \(WatchDateText.format(ticket.departureAt, timezone: ticket.timezone, pattern: "M月d日 HH:mm"))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(WatchTicket.display(ticket.carriage, fallback: "车厢待补充")) · \(WatchTicket.display(ticket.seat, fallback: "座位待补充"))")
                .font(.caption)
            if let seatClass = ticket.seatClass, !seatClass.isEmpty {
                Text(seatClass).font(.caption2).foregroundStyle(.secondary)
            }
            if let fare = ticket.fare, !fare.isEmpty {
                Text("票价 \(fare)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WatchTicketDetailView: View {
    let ticket: WatchTicket

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                Section {
                    HStack {
                        Text(ticket.train).font(.title3.bold())
                        Spacer()
                        Text(ticket.status(at: context.date)).foregroundStyle(.green)
                    }
                    Text("状态按计划时间推算").font(.caption2).foregroundStyle(.secondary)
                }
                Section("行程") {
                    detail("出发站", ticket.origin)
                    detail("到达站", ticket.destination)
                    detail("计划发车", WatchDateText.format(ticket.departureAt, timezone: ticket.timezone, pattern: "yyyy年M月d日 HH:mm"))
                    detail("计划到站", ticket.arrivalAt.map { WatchDateText.format($0, timezone: ticket.timezone, pattern: "yyyy年M月d日 HH:mm") } ?? "待补充")
                }
                Section("乘车信息") {
                    detail("席别", WatchTicket.display(ticket.seatClass ?? "", fallback: "待补充"))
                    detail("车厢", WatchTicket.display(ticket.carriage, fallback: "待补充"))
                    detail("座位", WatchTicket.display(ticket.seat, fallback: "待补充"))
                    detail("票价", WatchTicket.display(ticket.fare ?? "", fallback: "待补充"))
                    detail("候车室", WatchTicket.display(ticket.waitingRoom, fallback: "待公布"))
                    detail("检票口", WatchTicket.display(ticket.gate, fallback: "待公布"))
                }
                Section("数据来源") {
                    Text(ticket.fieldSources.values.contains("手动修改") ? "信息来自导入截图及手动修改" : WatchTicket.display(ticket.sourceText, fallback: "信息来自导入截图"))
                    Text("最后编辑：\(ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("离线显示最后一次同步数据，不代表铁路实时信息")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(ticket.train)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
