import SwiftUI

enum TripPalette {
    static func page(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.075, green: 0.08, blue: 0.085)
            : Color(uiColor: .systemGroupedBackground)
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.16, green: 0.17, blue: 0.18)
            : Color(uiColor: .secondarySystemGroupedBackground)
    }
}

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
    @Environment(\.colorScheme) private var colorScheme
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
        .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TicketRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket
    var body: some View {
        TicketCardContent(ticket: ticket)
            .padding(15)
            .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
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
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket
    @Binding var demoFeedback: String?
    let onSync: () -> Void
    let onDemo: () -> Void
    let onDelete: () -> Void
    let onUpdate: (Ticket) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var showingEditor = false
    @State private var editingField: TicketEditField?
    @State private var showingProvenance = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button { editingField = nil; showingEditor = true } label: {
                    TicketSummaryPanel(ticket: ticket)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑车票信息")
                Button { editingField = .waitingRoom; showingEditor = true } label: {
                    TicketOnsitePanel(ticket: ticket)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑候车室和检票口")
                DisclosureGroup("来源与时间", isExpanded: $showingProvenance) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ticket.sourceText)
                        Text("导入于 \(ticket.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("更新于 \(ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("状态依据计划时间推算")
                    }
                    .padding(.top, 5)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onSync) {
                    Label("显示到智能叠放", systemImage: "applewatch.and.arrow.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onDemo) {
                    Image(systemName: "play.rectangle")
                        .frame(width: 38, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("启动 15 分钟智能叠放演示")
                .help("启动 15 分钟智能叠放演示")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .background(TripPalette.page(for: colorScheme).ignoresSafeArea())
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
        .alert("确认删除这张车票？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) { onDelete(); dismiss() }
        } message: {
            Text("此操作将删除本机保存的这张车票，且无法恢复。")
        }
        .alert("智能叠放演示", isPresented: Binding(
            get: { demoFeedback != nil },
            set: { if !$0 { demoFeedback = nil } }
        )) {
            Button("知道了") { demoFeedback = nil }
        } message: {
            Text(demoFeedback ?? "")
        }
    }

}

struct TicketSummaryPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(display(ticket.train)).font(.title2.bold())
                Spacer()
                StatusBadge(status: ticket.status)
            }
            HStack(spacing: 10) {
                Text(display(ticket.from)).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.subheadline).foregroundStyle(.secondary)
                Text(display(ticket.to)).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            scheduleRow("出发", date: ticket.plannedDepartureAt, fallbackDay: ticket.date, time: ticket.departTime)
            scheduleRow("到达", date: ticket.plannedArrivalAt, fallbackDay: arrivalDay, time: ticket.arriveTime)
            HStack(spacing: 6) {
                Text(display(ticket.seatClass))
                Text("·").foregroundStyle(.tertiary)
                Text(display(ticket.carriage))
                Text("·").foregroundStyle(.tertiary)
                Text(display(ticket.seat))
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("订单号").font(.caption2).foregroundStyle(.secondary)
                    Text(ticket.orderNumber.isEmpty ? "待补充" : ticket.orderNumber)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ticket.orderNumber.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("票价").font(.caption2).foregroundStyle(.secondary)
                    Text(display(ticket.fare)).font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
    }

    private var arrivalDay: String {
        guard let arrival = ticket.plannedArrivalAt else { return "" }
        let formatter = DateFormatter()
        formatter.timeZone = ticket.displayTimezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: arrival)
    }

    private func scheduleRow(_ label: String, date: Date?, fallbackDay: String, time: String) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            Text(date.map { formatted($0) } ?? display(fallbackDay))
            Text(display(time, fallback: "--:--")).monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = ticket.displayTimezone
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private func display(_ value: String, fallback: String = "待补充") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct TicketOnsitePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            onsiteValue("候车室", ticket.waitingRoom)
            Divider()
            onsiteValue("检票口", ticket.gate)
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
    }

    private func onsiteValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(display(value, fallback: "待公布"))
                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func display(_ value: String, fallback: String = "待补充") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum TicketEditField: String, Hashable, Identifiable {
    case train, travelDate, departureTime, arrivalDate, arrivalTime, from, to
    case carriage, seat, seatClass, fare, orderNumber, waitingRoom, gate
    var id: String { rawValue }
}

struct TicketEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket
    let initialFocus: TicketEditField?
    let onSave: ((Ticket) -> Void)?
    let onSaveFields: ((TicketEditFields) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var fields: TicketEditFields
    @State private var validationMessage: String?
    @FocusState private var focusedField: TicketEditField?
    @State private var pickerField: TicketEditField?
    @State private var pickerValue = Date()

    init(ticket: Ticket, initialFocus: TicketEditField? = nil,
         initialFields: TicketEditFields? = nil, onSave: @escaping (Ticket) -> Void) {
        self.ticket = ticket
        self.initialFocus = initialFocus
        self.onSave = onSave
        self.onSaveFields = nil
        _fields = State(initialValue: initialFields ?? TicketEditFields(ticket: ticket))
    }

    init(ticket: Ticket, initialFields: TicketEditFields,
         onSaveFields: @escaping (TicketEditFields) -> Void) {
        self.ticket = ticket
        self.initialFocus = nil
        self.onSave = nil
        self.onSaveFields = onSaveFields
        _fields = State(initialValue: initialFields)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 11) {
                        textInput("车次", $fields.train, "如 G1234", .train, font: .title2.bold())
                        HStack(spacing: 10) {
                            textInput("出发站", $fields.from, "出发站", .from, font: .title3.weight(.semibold))
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            textInput("到达站", $fields.to, "到达站", .to, font: .title3.weight(.semibold))
                                .multilineTextAlignment(.trailing)
                        }
                        scheduleInput("出发", day: fields.travelDate, time: fields.departureTime,
                                      dayField: .travelDate, timeField: .departureTime)
                        scheduleInput("到达", day: fields.arrivalDate, time: fields.arrivalTime,
                                      dayField: .arrivalDate, timeField: .arrivalTime)
                        HStack(spacing: 6) {
                            textInput("席别", $fields.seatClass, "席别", .seatClass)
                            Text("·").foregroundStyle(.tertiary)
                            textInput("车厢", $fields.carriage, "车厢", .carriage)
                            Text("·").foregroundStyle(.tertiary)
                            textInput("座位", $fields.seat, "座位", .seat)
                        }
                        Divider()
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            labeledInput("订单号", $fields.orderNumber, "待补充", .orderNumber)
                            labeledInput("票价", $fields.fare, "待补充", .fare)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                    .padding(16)
                    .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 16) {
                        labeledInput("候车室", $fields.waitingRoom, "待公布", .waitingRoom)
                        Divider()
                        labeledInput("检票口", $fields.gate, "待公布", .gate)
                    }
                    .frame(height: 40)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
                    if let validationMessage { Text(validationMessage).font(.subheadline).foregroundStyle(.red) }
                }
                .padding(16)
            }
            .background(TripPalette.page(for: colorScheme).ignoresSafeArea())
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
            .sheet(item: $pickerField) { field in
                NavigationStack {
                    Group {
                        if field == .travelDate || field == .arrivalDate {
                            DatePicker("选择日期", selection: $pickerValue, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                        } else {
                            DatePicker("选择时间", selection: $pickerValue, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                        }
                    }
                    .padding()
                    .environment(\.timeZone, ticket.displayTimezone)
                    .navigationTitle(field == .travelDate || field == .arrivalDate ? "选择日期" : "选择时间")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { pickerField = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { applyPicker(field) } }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func applyInitialFocus() {
        guard let initialFocus else { return }
        focusedField = initialFocus
    }

    private func textInput(_ label: String, _ text: Binding<String>, _ prompt: String,
                           _ field: TicketEditField, font: Font = .subheadline.weight(.medium)) -> some View {
        TextField(prompt, text: text)
            .font(font)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .accessibilityLabel(label)
    }

    private func labeledInput(_ label: String, _ text: Binding<String>, _ prompt: String,
                              _ field: TicketEditField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            textInput(label, text, prompt, field, font: .subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scheduleInput(_ label: String, day: String, time: String,
                               dayField: TicketEditField, timeField: TicketEditField) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            Button(day.isEmpty ? "选择日期" : day) { openPicker(dayField, day: day, time: time) }
            Button(time.isEmpty ? "选择时间" : time) { openPicker(timeField, day: day, time: time) }
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .tint(.indigo)
    }

    private func openPicker(_ field: TicketEditField, day: String, time: String) {
        focusedField = nil
        let formatter = DateFormatter()
        formatter.timeZone = ticket.displayTimezone
        formatter.dateFormat = "yyyy-MM-dd"
        let selectedDay = day.isEmpty ? formatter.string(from: Date()) : day
        pickerValue = Ticket.scheduleDate(day: selectedDay, time: time.isEmpty ? "12:00" : time,
                                          timezone: ticket.displayTimezone) ?? Date()
        pickerField = field
    }

    private func applyPicker(_ field: TicketEditField) {
        let formatter = DateFormatter()
        formatter.timeZone = ticket.displayTimezone
        switch field {
        case .travelDate, .arrivalDate: formatter.dateFormat = "yyyy-MM-dd"
        case .departureTime, .arrivalTime: formatter.dateFormat = "HH:mm"
        default: return
        }
        let value = formatter.string(from: pickerValue)
        switch field {
        case .travelDate: fields.travelDate = value
        case .arrivalDate: fields.arrivalDate = value
        case .departureTime: fields.departureTime = value
        case .arrivalTime: fields.arrivalTime = value
        default: break
        }
        pickerField = nil
    }

    private func save() {
        if let onSaveFields {
            onSaveFields(fields)
            return
        }
        switch fields.updatedTicket(from: ticket) {
        case .success(let updated): onSave?(updated)
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
    var orderNumber: String
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
        orderNumber = ticket.orderNumber
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
        set("orderNumber", original.orderNumber, orderNumber) { $0.orderNumber = $1 }
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
