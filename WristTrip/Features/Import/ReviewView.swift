import SwiftUI
import PhotosUI
import UIKit

struct ReviewView: View {
    let initialImage: UIImage?
    let onRecognitionSuccess: () -> Void
    let onSave: (Ticket) -> Void
    let isDuplicate: (Ticket) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var didLoadInitialImage = false
    @State private var didReportRecognitionSuccess = false
    @State private var showingEditor = false
    @State private var showingImageZoom = false

    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var recognitionID = UUID()
    @State private var isRecognizing = false
    @State private var recognitionError: String?
    @State private var validationMessage: String?
    @State private var recognized: [String: String] = [:]
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

    init(initialImage: UIImage? = nil, onRecognitionSuccess: @escaping () -> Void = {},
         onSave: @escaping (Ticket) -> Void,
         isDuplicate: @escaping (Ticket) -> Bool) {
        self.initialImage = initialImage
        self.onRecognitionSuccess = onRecognitionSuccess
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
                            Button("重试识别") {
                                if let image { recognize(image) }
                            }
                            .buttonStyle(.bordered)
                        }
                        Button { showingEditor = true } label: {
                            TicketSummaryPanel(ticket: previewTicket, showsStatus: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑识别出的车票信息")
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
            .fullScreenCover(isPresented: $showingImageZoom) {
                if let image {
                    NavigationStack {
                        ZoomableTicketImage(image: image)
                            .background(.black)
                            .ignoresSafeArea(edges: .bottom)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("完成") { showingImageZoom = false }
                                        .tint(.white)
                                }
                            }
                            .toolbarBackground(.black, for: .navigationBar)
                            .toolbarBackground(.visible, for: .navigationBar)
                    }
                    .preferredColorScheme(.dark)
                }
            }
        }
        .onChange(of: selectedItem) { _, item in recognize(item) }
        .task(id: initialImage?.hash) {
            guard !didLoadInitialImage, let initialImage else { return }
            didLoadInitialImage = true
            recognize(initialImage)
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showingImageZoom = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if image != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(9)
                            .background(.black.opacity(0.65), in: Circle())
                            .padding(12)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(image == nil)
            .accessibilityLabel("放大查看原图")

            HStack(spacing: 12) {
                Text(isRecognizing ? "正在本机识别" : image == nil ? "尚未选择图片" : "点击图片可放大查看")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(image == nil ? "选择图片" : "更换图片", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
            }
            Text("原图只用于本次核对，不随车票保存")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                            ("到站日期", arrivalDate), ("计划到站", arrival), ("出发站", from),
                            ("到达站", to), ("车厢", carriage), ("座位", seat)]
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
                            seat: trimmed(seat), waitingRoom: trimmed(waitingRoom),
                            gate: trimmed(gate),
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
                let result = try await service.recognizeFields(in: selectedImage)
                guard recognitionID == requestID else { return }
                image = selectedImage
                apply(result)
                reportRecognitionSuccess()
            } catch {
                guard recognitionID == requestID else { return }
                recognitionError = "图片读取或 OCR 识别失败：\(error.localizedDescription)"
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
                let fields = try await TicketOCRService().recognizeFields(in: selectedImage)
                guard recognitionID == requestID else { return }
                apply(fields)
                reportRecognitionSuccess()
            } catch {
                guard recognitionID == requestID else { return }
                recognitionError = "OCR 识别失败：\(error.localizedDescription)"
            }
            if recognitionID == requestID { isRecognizing = false }
        }
    }

    private func reportRecognitionSuccess() {
        guard !didReportRecognitionSuccess else { return }
        didReportRecognitionSuccess = true
        onRecognitionSuccess()
    }

    private func clearFields() {
        image = nil
        recognitionError = nil
        validationMessage = nil
        recognized = [:]
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

private struct ZoomableTicketImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TicketImageScrollView {
        let view = TicketImageScrollView()
        view.backgroundColor = .black
        view.delegate = context.coordinator
        view.minimumZoomScale = 1
        view.maximumZoomScale = 8
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.imageView.image = image
        context.coordinator.imageView = view.imageView
        return view
    }

    func updateUIView(_ view: TicketImageScrollView, context: Context) {
        if view.imageView.image !== image {
            view.imageView.image = image
            view.setZoomScale(view.minimumZoomScale, animated: false)
        }
        context.coordinator.imageView = view.imageView
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let horizontalInset = max(0, (scrollView.bounds.width - imageView.frame.width) / 2)
            let verticalInset = max(0, (scrollView.bounds.height - imageView.frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset,
                                                   bottom: verticalInset, right: horizontalInset)
        }
    }
}

private final class TicketImageScrollView: UIScrollView {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard zoomScale == minimumZoomScale else { return }
        imageView.frame = bounds
        contentSize = bounds.size
    }
}
