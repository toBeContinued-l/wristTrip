import SwiftUI

private struct TicketCardContent: View {
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(display(ticket.train, missing: "车次待补充")).font(.title3.weight(.bold))
                Text(travelDay).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                StatusBadge(status: ticket.status, compact: true)
            }
            HStack(alignment: .top, spacing: 8) {
                stop(ticket.from, time: ticket.departTime, trailing: false)
                VStack(spacing: 3) {
                    Text(durationText).font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity).padding(.top, 3)
                stop(ticket.to, time: ticket.arriveTime, trailing: true)
            }
            HStack(spacing: 5) {
                Image(systemName: "ticket").foregroundStyle(.secondary)
                Text([display(ticket.carriage, missing: "车厢待补充"),
                      display(ticket.seat, missing: "座位待补充"),
                      display(ticket.seatClass, missing: "席别待补充"),
                      ticket.fare.isEmpty ? "票价待补充" : "票价 \(ticket.fare)"].joined(separator: " · "))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stop(_ name: String, time: String, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(display(name, missing: "站名待补充"))
                .font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(display(time, missing: "--:--"))
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private var travelDay: String {
        guard let date = ticket.plannedDepartureAt else { return display(ticket.date, missing: "日期待补充") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = ticket.displayTimezone
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: date)
    }

    private var durationText: String {
        let minutes: Int?
        if let start = ticket.plannedDepartureAt, let end = ticket.plannedArrivalAt, end > start {
            minutes = Int(end.timeIntervalSince(start) / 60)
        } else {
            minutes = ticket.durationMinutes
        }
        guard let minutes, minutes > 0 else { return "历时待补充" }
        return minutes >= 60 ? "\(minutes / 60)时\(minutes % 60)分" : "\(minutes)分"
    }

    private func display(_ value: String, missing: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? missing : trimmed
    }
}

struct CurrentTicketCard: View {
    let ticket: Ticket
    let onSync: () -> Void
    let onWatch: () -> Void
    let onDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onDetail) {
                TicketCardContent(ticket: ticket).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Button(action: onSync) { Label("显示到智能叠放", systemImage: "applewatch.and.arrow.forward") }
                    .buttonStyle(.borderedProminent)
                Button(action: onWatch) { Image(systemName: "eye") }
                    .buttonStyle(.bordered).accessibilityLabel("预览手表卡片")
                Spacer(minLength: 0)
            }
            Text(ticket.syncText).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TicketRow: View {
    let ticket: Ticket
    var body: some View {
        TicketCardContent(ticket: ticket)
            .padding(15)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusBadge: View {
    let status: TicketStatus
    var compact = false
    var body: some View {
        Text(status.rawValue)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(status == .arrived ? Color.secondary : Color.indigo)
    }
}

struct TicketDetailView: View {
    let ticket: Ticket
    let onSync: () -> Void
    let onDelete: () -> Void
    let onUpdate: (Ticket) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var showingEditor = false
    @State private var editingField: TicketEditField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TicketCardContent(ticket: ticket)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                fieldSection("车票信息", fields: [
                    ("车次", ticket.train, "train"),
                    ("出行日期", ticket.date, "travelDate"),
                    ("计划发车", ticket.departTime, "departureTime"),
                    ("到站日期", arrivalDay, "arrivalDate"),
                    ("计划到站", ticket.arriveTime, "arrivalTime"),
                    ("出发站", ticket.from, "from"), ("到达站", ticket.to, "to"),
                    ("车厢", ticket.carriage, "carriage"), ("座位", ticket.seat, "seat"),
                    ("席别", ticket.seatClass, "seatClass"), ("票价", ticket.fare, "fare")
                ])
                fieldSection("现场信息", fields: [
                    ("候车室", ticket.waitingRoom, "waitingRoom"),
                    ("检票口", ticket.gate, "gate")
                ])
                VStack(alignment: .leading, spacing: 5) {
                    Text(ticket.sourceText)
                    Text("导入于 \(ticket.importedAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("更新于 \(ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("状态依据计划时间推算")
                }
                .font(.caption).foregroundStyle(.secondary)
                Button(action: onSync) { Label("显示到智能叠放", systemImage: "applewatch.and.arrow.forward") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("车票详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { editingField = nil; showingEditor = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("编辑车票")
                Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("删除车票")
            }
        }
        .sheet(isPresented: $showingEditor) {
            TicketEditorView(ticket: ticket, initialFocus: editingField) { updated in
                onUpdate(updated)
                showingEditor = false
            }
        }
        .confirmationDialog("删除这张车票？", isPresented: $confirmingDelete) {
            Button("删除车票", role: .destructive) { onDelete(); dismiss() }
        }
    }

    private var arrivalDay: String {
        guard let arrival = ticket.plannedArrivalAt else { return "" }
        let formatter = DateFormatter()
        formatter.timeZone = ticket.displayTimezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: arrival)
    }

    private func fieldSection(_ title: String, fields: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(fields, id: \.0) { field in
                Button {
                    editingField = TicketEditField(rawValue: field.2)
                    showingEditor = true
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(field.0).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(field.1.isEmpty ? "待补充" : field.1).multilineTextAlignment(.trailing)
                            if let source = ticket.fieldSources[field.2] {
                                Text(source.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑\(field.0)，当前\(field.1.isEmpty ? "待补充" : field.1)")
                if field.0 != fields.last?.0 { Divider() }
            }
        }
        .font(.subheadline)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

enum TicketEditField: String, Hashable {
    case train, travelDate, departureTime, arrivalDate, arrivalTime, from, to
    case carriage, seat, seatClass, fare, waitingRoom, gate
}

struct TicketEditorView: View {
    let ticket: Ticket
    let initialFocus: TicketEditField?
    let onSave: (Ticket) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fields: TicketEditFields
    @State private var validationMessage: String?
    @FocusState private var focusedField: TicketEditField?

    init(ticket: Ticket, initialFocus: TicketEditField? = nil, onSave: @escaping (Ticket) -> Void) {
        self.ticket = ticket
        self.initialFocus = initialFocus
        self.onSave = onSave
        _fields = State(initialValue: TicketEditFields(ticket: ticket))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("行程") {
                    row("车次", $fields.train, "如 G1234", .train)
                    row("出行日期", $fields.travelDate, "YYYY-MM-DD", .travelDate)
                    row("计划发车", $fields.departureTime, "HH:mm", .departureTime)
                    row("到站日期", $fields.arrivalDate, "YYYY-MM-DD", .arrivalDate)
                    row("计划到站", $fields.arrivalTime, "HH:mm", .arrivalTime)
                    row("出发站", $fields.from, "站名", .from)
                    row("到达站", $fields.to, "站名", .to)
                }
                Section("座位") {
                    row("车厢", $fields.carriage, "待补充", .carriage)
                    row("座位", $fields.seat, "待补充", .seat)
                    row("席别", $fields.seatClass, "如 二等座", .seatClass)
                    row("票价", $fields.fare, "如 ¥25", .fare)
                }
                Section("现场信息") {
                    row("候车室", $fields.waitingRoom, "待公布", .waitingRoom)
                    row("检票口", $fields.gate, "待公布", .gate)
                }
                if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
            }
            .navigationTitle("编辑车票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold) }
            }
            .onAppear { applyInitialFocus() }
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                applyInitialFocus()
            }
        }
    }

    private func applyInitialFocus() {
        guard let initialFocus else { return }
        focusedField = initialFocus
    }

    private func row(_ label: String, _ text: Binding<String>, _ prompt: String, _ field: TicketEditField) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 76, alignment: .leading)
            TextField(prompt, text: text).multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .accessibilityLabel(label)
        }
    }

    private func save() {
        switch fields.updatedTicket(from: ticket) {
        case .success(let updated): onSave(updated)
        case .failure(let error): validationMessage = error.localizedDescription
        }
    }
}

struct TicketEditFields {
    var train: String
    var travelDate: String
    var departureTime: String
    var arrivalDate: String
    var arrivalTime: String
    var from: String
    var to: String
    var carriage: String
    var seat: String
    var seatClass: String
    var fare: String
    var waitingRoom: String
    var gate: String

    init(ticket: Ticket) {
        train = ticket.train
        travelDate = Self.day(ticket.plannedDepartureAt, timezone: ticket.displayTimezone) ?? ticket.date
        departureTime = ticket.departTime
        arrivalDate = Self.day(ticket.plannedArrivalAt, timezone: ticket.displayTimezone) ?? ""
        arrivalTime = ticket.arriveTime
        from = ticket.from
        to = ticket.to
        carriage = ticket.carriage
        seat = ticket.seat
        seatClass = ticket.seatClass
        fare = ticket.fare
        waitingRoom = ticket.waitingRoom == "待公布" ? "" : ticket.waitingRoom
        gate = ticket.gate == "待公布" ? "" : ticket.gate
    }

    func updatedTicket(from original: Ticket, now: Date = Date()) -> Result<Ticket, TicketEditError> {
        let day = trimmed(travelDate), departure = trimmed(departureTime)
        let arrivalDay = trimmed(arrivalDate), arrival = trimmed(arrivalTime)
        guard (day.isEmpty && departure.isEmpty) || Ticket.scheduleDate(day: day, time: departure, timezone: original.displayTimezone) != nil else {
            return .failure(.invalidDeparture)
        }
        guard (arrivalDay.isEmpty && arrival.isEmpty) || Ticket.scheduleDate(day: arrivalDay, time: arrival, timezone: original.displayTimezone) != nil else {
            return .failure(.invalidArrival)
        }
        let start = day.isEmpty ? nil : Ticket.scheduleDate(day: day, time: departure, timezone: original.displayTimezone)
        let end = arrivalDay.isEmpty ? nil : Ticket.scheduleDate(day: arrivalDay, time: arrival, timezone: original.displayTimezone)
        if let start, let end, end <= start { return .failure(.arrivalBeforeDeparture) }

        var updated = original
        var changed = false
        func set(_ key: String, _ old: String, _ value: String, _ write: (inout Ticket, String) -> Void) {
            let cleaned = trimmed(value)
            guard old != cleaned else { return }
            write(&updated, cleaned)
            updated.fieldSources[key] = .manual
            changed = true
        }
        set("train", original.train, train) { $0.train = $1 }
        set("travelDate", Self.day(original.plannedDepartureAt, timezone: original.displayTimezone) ?? original.date, day) { $0.date = $1 }
        set("departureTime", original.departTime, departure) { $0.departTime = $1 }
        set("arrivalDate", Self.day(original.plannedArrivalAt, timezone: original.displayTimezone) ?? "", arrivalDay) { _, _ in }
        set("arrivalTime", original.arriveTime, arrival) { $0.arriveTime = $1 }
        set("from", original.from, from) { $0.from = $1 }
        set("to", original.to, to) { $0.to = $1 }
        set("carriage", original.carriage, carriage) { $0.carriage = $1 }
        set("seat", original.seat, seat) { $0.seat = $1 }
        set("seatClass", original.seatClass, seatClass) { $0.seatClass = $1 }
        set("fare", original.fare, fare) { $0.fare = $1 }
        set("waitingRoom", original.waitingRoom == "待公布" ? "" : original.waitingRoom, waitingRoom) {
            $0.waitingRoom = $1.isEmpty ? "待公布" : $1
        }
        set("gate", original.gate == "待公布" ? "" : original.gate, gate) {
            $0.gate = $1.isEmpty ? "待公布" : $1
            $0.normalizedGates = Ticket.normalizeGates($0.gate)
            $0.gateQueriedAt = nil
            $0.gateQueryRawResponse = nil
        }
        guard changed || start != original.plannedDepartureAt || end != original.plannedArrivalAt else {
            return .success(original)
        }
        let scheduleChanged = start != original.plannedDepartureAt || end != original.plannedArrivalAt
        updated.plannedDepartureAt = start
        updated.plannedArrivalAt = end
        if let start, let end {
            updated.durationMinutes = Int(end.timeIntervalSince(start) / 60)
        } else if scheduleChanged {
            updated.durationMinutes = nil
        }
        updated.updatedAt = now
        updated.sourceText = "来自导入截图与人工修改"
        updated.syncText = "已修改 · 尚未同步"
        updated.refreshStatus(at: now)
        return .success(updated)
    }

    private static func day(_ date: Date?, timezone: TimeZone) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum TicketEditError: LocalizedError {
    case invalidDeparture, invalidArrival, arrivalBeforeDeparture
    var errorDescription: String? {
        switch self {
        case .invalidDeparture: "请填写有效的出行日期和发车时间（YYYY-MM-DD、HH:mm），或两项都留空"
        case .invalidArrival: "请填写有效的到站日期和时间（YYYY-MM-DD、HH:mm），或两项都留空"
        case .arrivalBeforeDeparture: "计划到站必须晚于计划发车，请核对跨日日期"
        }
    }
}
