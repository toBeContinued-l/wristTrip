import SwiftUI
import PhotosUI
import UIKit

struct ReviewView: View {
    let initialImage: UIImage?
    let onSave: (Ticket) -> Void
    let isDuplicate: (Ticket) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var didLoadInitialImage = false
    @State private var showingEditor = false

    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var recognitionID = UUID()
    @State private var isRecognizing = false
    @State private var recognitionError: String?
    @State private var validationMessage: String?
    @State private var recognized: [String: String] = [:]
    @State private var visibleSeats: [OCRSeat] = []
    @State private var recognizedDuration: Int?

    @State private var train = ""
    @State private var travelDate = ""
    @State private var departure = ""
    @State private var arrivalDate = ""
    @State private var arrival = ""
    @State private var from = ""
    @State private var to = ""
    @State private var carriage = ""
    @State private var seat = ""
    @State private var seatClass = ""
    @State private var fare = ""
    @State private var orderNumber = ""
    @State private var waitingRoom = ""
    @State private var gate = ""

    init(initialImage: UIImage? = nil, onSave: @escaping (Ticket) -> Void,
         isDuplicate: @escaping (Ticket) -> Bool) {
        self.initialImage = initialImage
        self.onSave = onSave
        self.isDuplicate = isDuplicate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("核对车票").font(.title2.bold())
                    imageSection
                    if image != nil {
                        if let recognitionError {
                            Label(recognitionError, systemImage: "exclamationmark.circle")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                        if !visibleSeats.isEmpty { seatPicker }
                        Button { showingEditor = true } label: {
                            TicketSummaryPanel(ticket: previewTicket)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑识别出的车票信息")
                        Button { showingEditor = true } label: {
                            TicketOnsitePanel(ticket: previewTicket)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑候车室和检票口")
                        if let validationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(.red)
                        }
                        Button { save(draft: false) } label: {
                            Label("确认添加车票", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isRecognizing)
                        Button("保存为草稿") { save(draft: true) }
                            .frame(maxWidth: .infinity)
                            .disabled(isRecognizing)
                    }
                }
                .padding(20)
            }
            .background(TripPalette.page(for: colorScheme).ignoresSafeArea())
            .navigationTitle("截图识别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .sheet(isPresented: $showingEditor) {
                TicketEditorView(ticket: previewTicket, initialFields: reviewEditFields) { editedFields in
                    applyEdited(editedFields)
                    showingEditor = false
                }
            }
        }
        .onChange(of: selectedItem) { _, item in recognize(item) }
        .onAppear {
            guard !didLoadInitialImage, let initialImage else { return }
            didLoadInitialImage = true
            recognize(initialImage)
        }
    }

    private var imageSection: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 96, height: 124)
            .clipped()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 10) {
                Text(isRecognizing ? "正在本机识别" : image == nil ? "尚未选择图片" : "请核对原图")
                    .font(.subheadline.weight(.semibold))
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(image == nil ? "从相册选择" : "更换图片", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
                Text("原图只用于本次核对，不随车票保存")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var seatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("截图中可见的座位").font(.headline)
            Picker("选择座位", selection: Binding(
                get: { visibleSeats.first { $0.carriage == carriage && $0.seat == seat && $0.seatClass == seatClass } },
                set: { option in selectSeat(option) }
            )) {
                Text(carriage.isEmpty && seat.isEmpty ? "暂不选择" : "手动修改")
                    .tag(Optional<OCRSeat>.none)
                ForEach(visibleSeats, id: \.self) { option in
                    Text([option.carriage, option.seat, option.seatClass].filter { !$0.isEmpty }.joined(separator: " · ")).tag(Optional(option))
                }
            }
            .pickerStyle(.menu)
            Text("仅列出图片中可见且能对应的座位；其他乘客请展开后重新分享。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func selectSeat(_ option: OCRSeat?) {
        carriage = option?.carriage ?? ""
        seat = option?.seat ?? ""
        seatClass = option?.seatClass ?? ""
        if let option {
            recognized["carriage"] = option.carriage
            recognized["seat"] = option.seat
            if !option.seatClass.isEmpty { recognized["seatClass"] = option.seatClass }
        } else {
            recognized.removeValue(forKey: "carriage")
            recognized.removeValue(forKey: "seat")
            recognized.removeValue(forKey: "seatClass")
        }
    }

    private var previewTicket: Ticket { makeTicket(draft: true) }

    private var reviewEditFields: TicketEditFields {
        var fields = TicketEditFields(ticket: previewTicket)
        fields.arrivalDate = arrivalDate
        return fields
    }

    private func applyEdited(_ fields: TicketEditFields) {
        train = fields.train
        travelDate = fields.travelDate
        departure = fields.departureTime
        arrivalDate = fields.arrivalDate
        arrival = fields.arrivalTime
        from = fields.from
        to = fields.to
        carriage = fields.carriage
        seat = fields.seat
        seatClass = fields.seatClass
        fare = fields.fare
        orderNumber = fields.orderNumber
        waitingRoom = fields.waitingRoom
        gate = fields.gate
    }

    private func save(draft: Bool) {
        validationMessage = nil
        guard image != nil else { validationMessage = "请先选择车票图片"; return }
        let values = [train, travelDate, departure, arrivalDate, arrival, from, to, carriage, seat, seatClass, fare, orderNumber, waitingRoom, gate]
        if draft {
            guard values.contains(where: { !trimmed($0).isEmpty }) else {
                validationMessage = "至少填写一项车票信息后再保存草稿"
                return
            }
        } else {
            let required = [("车次", train), ("出行日期", travelDate), ("计划发车", departure),
                            ("到站日期", arrivalDate), ("计划到站", arrival), ("出发站", from), ("到达站", to)]
            let missing = required.filter { trimmed($0.1).isEmpty }.map(\.0)
            guard missing.isEmpty else {
                validationMessage = "请补充：" + missing.joined(separator: "、")
                return
            }
            guard let departureAt = Ticket.scheduleDate(day: trimmed(travelDate), time: trimmed(departure)),
                  let arrivalAt = Ticket.scheduleDate(day: trimmed(arrivalDate), time: trimmed(arrival)) else {
                validationMessage = "日期请填 YYYY-MM-DD，时间请填 HH:mm，并使用有效日历日期"
                return
            }
            guard arrivalAt > departureAt else {
                validationMessage = "计划到站必须晚于计划发车，请核对跨日日期"
                return
            }
        }
        let ticket = makeTicket(draft: draft)
        if !draft && isDuplicate(ticket) {
            validationMessage = "这张车票已添加，请在行程中查看或编辑"
            return
        }
        onSave(ticket)
    }

    private func makeTicket(draft: Bool) -> Ticket {
        let departureAt = Ticket.scheduleDate(day: trimmed(travelDate), time: trimmed(departure))
        let arrivalAt = Ticket.scheduleDate(day: trimmed(arrivalDate), time: trimmed(arrival))
        let duration = (departureAt != nil && arrivalAt != nil && arrivalAt! > departureAt!)
            ? Int(arrivalAt!.timeIntervalSince(departureAt!) / 60) : nil
        let values = ["train": train, "travelDate": travelDate, "departureTime": departure,
                      "arrivalDate": arrivalDate, "arrivalTime": arrival, "from": from, "to": to,
                      "carriage": carriage, "seat": seat, "seatClass": seatClass, "fare": fare,
                      "orderNumber": orderNumber,
                      "waitingRoom": waitingRoom, "gate": gate]
        let sources = values.reduce(into: [String: TicketFieldSource]()) { result, entry in
            guard !trimmed(entry.value).isEmpty else { return }
            result[entry.key] = recognized[entry.key] == trimmed(entry.value) ? .screenshot : .manual
        }
        var ticket = Ticket(id: UUID(), train: trimmed(train), date: trimmed(travelDate),
                            departTime: trimmed(departure), arriveTime: trimmed(arrival),
                            from: trimmed(from), to: trimmed(to), carriage: trimmed(carriage),
                            seat: trimmed(seat), waitingRoom: trimmed(waitingRoom).isEmpty ? "待公布" : trimmed(waitingRoom),
                            gate: trimmed(gate).isEmpty ? "待公布" : trimmed(gate),
                            status: .upcoming, syncText: draft ? "草稿 · 尚未同步" : "尚未同步",
                            sourceText: "来自导入截图与人工核对", plannedDepartureAt: departureAt,
                      plannedArrivalAt: arrivalAt, durationMinutes: duration ?? recognizedDuration,
                      fieldSources: sources, seatClass: trimmed(seatClass), fare: trimmed(fare),
                      orderNumber: trimmed(orderNumber))
        ticket.refreshStatus()
        return ticket
    }

    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func recognize(_ item: PhotosPickerItem?) {
        let requestID = UUID()
        recognitionID = requestID
        clearFields()
        guard let item else { return }
        isRecognizing = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let selectedImage = UIImage(data: data) else { throw TicketOCRServiceError.invalidImage }
                let service = TicketOCRService()
                let fields = try await service.recognizeLines(in: selectedImage)
                let result = service.parse(fields)
                guard recognitionID == requestID else { return }
                image = selectedImage
                apply(result)
            } catch {
                guard recognitionID == requestID else { return }
                recognitionError = error.localizedDescription
                if let data = try? await item.loadTransferable(type: Data.self) { image = UIImage(data: data) }
            }
            if recognitionID == requestID { isRecognizing = false }
        }
    }

    private func recognize(_ selectedImage: UIImage) {
        let requestID = UUID()
        recognitionID = requestID
        clearFields()
        image = selectedImage
        isRecognizing = true
        Task {
            do {
                let lines = try await TicketOCRService().recognizeLines(in: selectedImage)
                guard recognitionID == requestID else { return }
                apply(TicketOCRService().parse(lines))
            } catch {
                guard recognitionID == requestID else { return }
                recognitionError = error.localizedDescription
            }
            if recognitionID == requestID { isRecognizing = false }
        }
    }

    private func clearFields() {
        image = nil
        recognitionError = nil
        validationMessage = nil
        recognized = [:]
        visibleSeats = []
        recognizedDuration = nil
        train = ""; travelDate = ""; departure = ""; arrivalDate = ""; arrival = ""
        from = ""; to = ""; carriage = ""; seat = ""; seatClass = ""; fare = ""; orderNumber = ""; waitingRoom = ""; gate = ""
    }

    private func apply(_ fields: OCRTicketFields) {
        train = fields.train ?? ""
        travelDate = fields.travelDate ?? ""
        departure = fields.departureTime ?? ""
        arrivalDate = fields.arrivalDate ?? ""
        arrival = fields.arrivalTime ?? ""
        from = fields.from ?? ""
        to = fields.to ?? ""
        fare = fields.fare ?? ""
        orderNumber = fields.orderNumber ?? ""
        waitingRoom = fields.waitingRoom ?? ""
        gate = fields.gate ?? ""
        visibleSeats = fields.seats
        if let firstSeat = fields.seats.first {
            carriage = firstSeat.carriage
            seat = firstSeat.seat
            seatClass = firstSeat.seatClass
        }
        recognizedDuration = fields.durationMinutes
        recognized = ["train": train, "travelDate": travelDate, "departureTime": departure,
                      "arrivalDate": arrivalDate, "arrivalTime": arrival, "from": from, "to": to,
                      "carriage": carriage, "seat": seat, "seatClass": seatClass,
                      "waitingRoom": waitingRoom, "gate": gate, "fare": fare,
                      "orderNumber": orderNumber]
            .filter { !$0.value.isEmpty }
    }
}
