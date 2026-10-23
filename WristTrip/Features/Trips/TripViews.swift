import SwiftUI
import UIKit

enum TripPalette {
    static let moduleCornerRadius: CGFloat = 20

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
        }
        .padding(15)
        .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: TripPalette.moduleCornerRadius))
    }

}

struct TicketRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket
    var body: some View {
        TicketCardContent(ticket: ticket)
            .padding(15)
            .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: TripPalette.moduleCornerRadius))
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
    @State private var displayedTicket: Ticket
    let onSync: () -> Void
    let onDelete: () -> Void
    let onUpdate: (Ticket) -> Void
    let onRefresh: () async -> Void
    let onAppearRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var showingEditor = false
    @State private var returnToTripsAfterEdit = false
    @State private var showingProvenance = true

    init(ticket: Ticket, onSync: @escaping () -> Void,
         onDelete: @escaping () -> Void,
         onUpdate: @escaping (Ticket) -> Void,
         onRefresh: @escaping () async -> Void = {},
         onAppearRefresh: @escaping () -> Void = {}) {
        self.ticket = ticket
        _displayedTicket = State(initialValue: ticket)
        self.onSync = onSync
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        self.onRefresh = onRefresh
        self.onAppearRefresh = onAppearRefresh
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TicketSummaryPanel(ticket: displayedTicket)
                TicketOnsitePanel(ticket: displayedTicket)
                DisclosureGroup("来源与时间", isExpanded: $showingProvenance) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayedTicket.sourceText)
                        Text("导入于 \(displayedTicket.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("更新于 \(displayedTicket.updatedAt.formatted(date: .abbreviated, time: .shortened))")
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
        .refreshable { await onRefresh() }
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
        .navigationTitle("车票详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { onAppearRefresh() }
        .onChange(of: ticket) { _, updated in displayedTicket = updated }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingEditor = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("编辑车票")
                Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("删除车票")
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            if returnToTripsAfterEdit {
                returnToTripsAfterEdit = false
                dismiss()
            }
        }) {
            TicketEditorView(ticket: displayedTicket) { updated in
                displayedTicket = updated
                onUpdate(updated)
                returnToTripsAfterEdit = true
                showingEditor = false
            }
        }
        .alert("删除这张车票？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) { onDelete(); dismiss() }
        } message: {
            Text("此操作将删除本机保存的这张车票，且无法恢复。")
        }
    }

}

struct TicketSummaryPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let ticket: Ticket
    let showsStatus: Bool

    init(ticket: Ticket, showsStatus: Bool = true) {
        self.ticket = ticket
        self.showsStatus = showsStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(display(ticket.train)).font(.title2.bold())
                Spacer()
                if showsStatus {
                    StatusBadge(status: ticket.status)
                }
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
        .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: TripPalette.moduleCornerRadius))
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
        GeometryReader { proxy in
            let columnWidth = max(0, (proxy.size.width - 13) / 2)
            HStack(alignment: .top, spacing: 0) {
                TicketOnsiteValue(label: "候车室", value: ticket.waitingRoom)
                    .frame(width: columnWidth, alignment: .leading)
                Divider()
                TicketOnsiteValue(label: "检票口", value: ticket.gate)
                    .frame(width: columnWidth, alignment: .leading)
                    .padding(.leading, 12)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: TripPalette.moduleCornerRadius))
    }
}

struct TicketOnsiteDisplayValue: Equatable {
    let text: String

    init(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        text = trimmed.isEmpty ? "暂未获取到实时检票信息" : trimmed
    }
}

enum TicketOnsiteMarqueeBehavior {
    static let gap: CGFloat = 28

    static func shouldScroll(contentWidth: CGFloat, viewportWidth: CGFloat) -> Bool {
        contentWidth > viewportWidth
    }

    static func cycleDistance(contentWidth: CGFloat) -> CGFloat {
        contentWidth + gap
    }
}

private struct TicketOnsiteTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TicketOnsiteValue: View {
    let label: String
    let value: String
    @State private var contentWidth: CGFloat = 0
    @State private var marqueeOffset: CGFloat = 0

    private var displayedValue: String {
        TicketOnsiteDisplayValue(value).text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { proxy in
                let shouldScroll = TicketOnsiteMarqueeBehavior.shouldScroll(
                    contentWidth: contentWidth,
                    viewportWidth: proxy.size.width)
                Group {
                    if shouldScroll {
                        HStack(spacing: TicketOnsiteMarqueeBehavior.gap) {
                            marqueeText
                            marqueeText.accessibilityHidden(true)
                        }
                        .offset(x: marqueeOffset)
                    } else {
                        marqueeText
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .clipped()
                .onPreferenceChange(TicketOnsiteTextWidthKey.self) { width in
                    guard width != contentWidth else { return }
                    contentWidth = width
                    updateMarquee(viewportWidth: proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, width in
                    updateMarquee(viewportWidth: width)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("ticket-onsite-value-\(label)")
    }

    private var marqueeText: some View {
        Text(displayedValue)
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: TicketOnsiteTextWidthKey.self, value: proxy.size.width)
                }
            }
    }

    private func updateMarquee(viewportWidth: CGFloat) {
        let distance = TicketOnsiteMarqueeBehavior.cycleDistance(contentWidth: contentWidth)
        guard TicketOnsiteMarqueeBehavior.shouldScroll(contentWidth: contentWidth,
                                                       viewportWidth: viewportWidth) else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { marqueeOffset = 0 }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { marqueeOffset = 0 }
        withAnimation(.linear(duration: max(4, distance / 28)).repeatForever(autoreverses: false)) {
            marqueeOffset = -distance
        }
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
    let onSave: ((Ticket) -> Void)?
    let onSaveFields: ((TicketEditFields) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var fields: TicketEditFields
    @State private var validationMessage: String?
    @FocusState private var focusedField: TicketEditField?

    init(ticket: Ticket, onSave: @escaping (Ticket) -> Void) {
        self.ticket = ticket
        self.onSave = onSave
        self.onSaveFields = nil
        _fields = State(initialValue: TicketEditFields(ticket: ticket))
    }

    init(ticket: Ticket, initialFields: TicketEditFields,
         onSaveFields: @escaping (TicketEditFields) -> Void) {
        self.ticket = ticket
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
                        scheduleInput("出发", day: $fields.travelDate, time: $fields.departureTime,
                                      dayField: .travelDate, timeField: .departureTime)
                        scheduleInput("到达", day: $fields.arrivalDate, time: $fields.arrivalTime,
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
                            currencyInput
                                .frame(width: 90)
                        }
                    }
                    .padding(16)
                    .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: TripPalette.moduleCornerRadius))
                    HStack(alignment: .top, spacing: 16) {
                        labeledInput("候车室", $fields.waitingRoom, "待公布", .waitingRoom)
                        Divider()
                        labeledInput("检票口", $fields.gate, "待公布", .gate)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(TripPalette.card(for: colorScheme), in: RoundedRectangle(cornerRadius: TripPalette.moduleCornerRadius))
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
        }
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

    private func scheduleInput(_ label: String, day: Binding<String>, time: Binding<String>,
                               dayField: TicketEditField, timeField: TicketEditField) -> some View {
        let hasAnyValue = !day.wrappedValue.isEmpty || !time.wrappedValue.isEmpty
        return HStack(spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            scheduleTextInput(day, placeholder: "如 20261008", field: dayField, kind: .date,
                              required: hasAnyValue)
            scheduleTextInput(time, placeholder: "如 0842", field: timeField, kind: .time,
                              required: hasAnyValue)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }

    private func scheduleTextInput(_ value: Binding<String>, placeholder: String,
                                   field: TicketEditField, kind: ScheduleInputKind,
                                   required: Bool) -> some View {
        return FormattedScheduleTextField(
            text: value,
            placeholder: placeholder,
            kind: kind,
            validation: scheduleValidationState(value.wrappedValue, kind: kind, required: required)
        )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(scheduleValidationBorderColor(value.wrappedValue, kind: kind, required: required), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(field == .travelDate || field == .arrivalDate ? "日期" : "时间")
            .accessibilityHint(scheduleValidationHint(value.wrappedValue, kind: kind, required: required))
    }

    private func scheduleValidationColor(_ value: String, kind: ScheduleInputKind,
                                         required: Bool) -> Color {
        switch scheduleValidationState(value, kind: kind, required: required) {
        case .valid: return .clear
        case .incomplete: return .orange
        case .invalid: return .red
        }
    }

    private func scheduleValidationTextColor(_ value: String, kind: ScheduleInputKind,
                                             required: Bool) -> Color {
        switch scheduleValidationState(value, kind: kind, required: required) {
        case .valid: return .primary
        case .incomplete: return .orange
        case .invalid: return .red
        }
    }

    private func scheduleValidationBorderColor(_ value: String, kind: ScheduleInputKind,
                                               required: Bool) -> Color {
        scheduleValidationColor(value, kind: kind, required: required)
    }

    private func scheduleValidationState(_ value: String, kind: ScheduleInputKind,
                                         required: Bool) -> ScheduleValidation {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else { return required ? .incomplete : .valid }
        let limit = kind == .date ? 8 : 4
        guard digits.count == limit else { return .incomplete }
        let valid: Bool
        switch kind {
        case .date:
            valid = Ticket.scheduleDate(day: value, time: "00:00", timezone: ticket.displayTimezone) != nil
        case .time:
            valid = Ticket.scheduleDate(day: "2000-01-01", time: value,
                                        timezone: ticket.displayTimezone) != nil
        }
        return valid ? .valid : .invalid
    }

    private func scheduleValidationHint(_ value: String, kind: ScheduleInputKind,
                                        required: Bool) -> String {
        switch scheduleValidationState(value, kind: kind, required: required) {
        case .incomplete: return "请输入完整的\(kind == .date ? "八位日期" : "四位时间")"
        case .invalid: return "输入的\(kind == .date ? "日期" : "时间")不存在"
        case .valid: return ""
        }
    }

    private var currencyInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("票价").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text("¥").foregroundStyle(.secondary)
                TextField("金额", text: fareAmountBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: .fare)
            }
        }
    }

    private var fareAmountBinding: Binding<String> {
        Binding(
            get: { Self.numericFare(fields.fare) },
            set: { fields.fare = $0.isEmpty ? "" : "¥\(Self.numericFare($0))" }
        )
    }

    private static func numericFare(_ value: String) -> String {
        var result = ""
        var hasDecimal = false
        for character in value {
            if character.isNumber {
                result.append(character)
            } else if (character == "." || character == ",") && !hasDecimal {
                result.append(".")
                hasDecimal = true
            }
        }
        return result
    }

    private func save() {
        if let onSaveFields {
            onSaveFields(fields)
            return
        }
        guard let missingMessage = missingRequiredFieldMessage() else {
            switch fields.updatedTicket(from: ticket) {
            case .success(let updated): onSave?(updated)
            case .failure(let error): validationMessage = error.localizedDescription
            }
            return
        }
        validationMessage = missingMessage
    }

    private func missingRequiredFieldMessage() -> String? {
        let required: [(String, String)] = [
            ("车次", fields.train), ("出发站", fields.from), ("到达站", fields.to),
            ("车厢", fields.carriage), ("座位", fields.seat)
        ]
        if let missing = required.first(where: { trimmed($0.1).isEmpty }) {
            return "请填写\(missing.0)"
        }
        if trimmed(fields.travelDate).isEmpty || trimmed(fields.departureTime).isEmpty {
            return "请填写完整的出发日期和时间"
        }
        if trimmed(fields.arrivalDate).isEmpty || trimmed(fields.arrivalTime).isEmpty {
            return "请填写完整的到站日期和时间"
        }
        return nil
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ScheduleInputKind { case date, time }
private enum ScheduleValidation { case valid, incomplete, invalid }

enum ScheduleInputFormatter {
    struct EditResult: Equatable {
        let text: String
        let cursorPosition: Int
    }

    static func formattedText(_ value: String, kind: ScheduleInputKind) -> String {
        let clipped = String(value.filter(\.isNumber).prefix(kind == .date ? 8 : 4))
        switch kind {
        case .date:
            if clipped.count <= 4 { return clipped }
            if clipped.count <= 6 { return "\(clipped.prefix(4))-\(clipped.dropFirst(4))" }
            return "\(clipped.prefix(4))-\(clipped.dropFirst(4).prefix(2))-\(clipped.dropFirst(6))"
        case .time:
            if clipped.count <= 2 { return clipped }
            return "\(clipped.prefix(2)):\(clipped.dropFirst(2))"
        }
    }

    static func editedText(current: String, range: NSRange, replacement: String,
                           kind: ScheduleInputKind, backspaceOverSeparator: Bool = false) -> EditResult {
        let currentNSString = current as NSString
        let safeLocation = min(max(range.location, 0), currentNSString.length)
        let safeLength = min(max(range.length, 0), currentNSString.length - safeLocation)
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        let prefix = currentNSString.substring(with: NSRange(location: 0, length: safeLocation))
        let selected = currentNSString.substring(with: safeRange)
        let digitsBefore = prefix.filter(\.isNumber).count
        let selectedDigits = selected.filter(\.isNumber).count
        var digits = Array(current.filter(\.isNumber))
        let limit = kind == .date ? 8 : 4
        let start = min(digitsBefore, digits.count)
        var cursorDigitIndex: Int

        if backspaceOverSeparator && selectedDigits == 0 && start > 0 {
            digits.remove(at: start - 1)
            cursorDigitIndex = start - 1
        } else {
            let end = min(start + selectedDigits, digits.count)
            digits.removeSubrange(start..<end)
            let inserted = Array(replacement.filter(\.isNumber))
            digits.insert(contentsOf: inserted, at: start)
            cursorDigitIndex = start + inserted.count
        }

        if digits.count > limit {
            digits = Array(digits.prefix(limit))
        }
        cursorDigitIndex = min(cursorDigitIndex, digits.count)
        let text = formattedText(String(digits), kind: kind)
        return EditResult(text: text, cursorPosition: cursorPosition(forDigitOffset: cursorDigitIndex, in: text))
    }

    private static func cursorPosition(forDigitOffset offset: Int, in text: String) -> Int {
        var index = text.startIndex
        var digitsSeen = 0
        while index < text.endIndex {
            if digitsSeen == offset { return text.distance(from: text.startIndex, to: index) }
            if text[index].isNumber { digitsSeen += 1 }
            index = text.index(after: index)
        }
        return text.utf16.count
    }
}

private struct FormattedScheduleTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let kind: ScheduleInputKind
    let validation: ScheduleValidation

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.keyboardType = .numberPad
        textField.font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
            weight: .regular)
        textField.adjustsFontForContentSizeCategory = true
        textField.text = ScheduleInputFormatter.formattedText(text, kind: kind)
        context.coordinator.parent.text = textField.text ?? ""
        updateAppearance(textField)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self
        let formatted = ScheduleInputFormatter.formattedText(text, kind: kind)
        if text != formatted {
            text = formatted
            textField.text = formatted
        }
        textField.placeholder = placeholder
        updateAppearance(textField)
    }

    private func updateAppearance(_ textField: UITextField) {
        switch validation {
        case .valid: textField.textColor = .label
        case .incomplete: textField.textColor = .systemOrange
        case .invalid: textField.textColor = .systemRed
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FormattedScheduleTextField

        init(parent: FormattedScheduleTextField) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            let backspaceOverSeparator: Bool
            if string.isEmpty, range.length == 1,
               let selectedRange = textField.selectedTextRange,
               let start = textField.beginningOfDocument as UITextPosition? {
                let caret = textField.offset(from: start, to: selectedRange.start)
                let selectedText = (current as NSString).substring(with: range)
                backspaceOverSeparator = caret == range.location + range.length
                    && selectedText.rangeOfCharacter(from: .decimalDigits) == nil
            } else {
                backspaceOverSeparator = false
            }

            let result = ScheduleInputFormatter.editedText(
                current: current,
                range: range,
                replacement: string,
                kind: parent.kind,
                backspaceOverSeparator: backspaceOverSeparator)
            textField.text = result.text
            parent.text = result.text
            if let position = textField.position(from: textField.beginningOfDocument,
                                                  offset: result.cursorPosition) {
                textField.selectedTextRange = textField.textRange(from: position, to: position)
            }
            return false
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
