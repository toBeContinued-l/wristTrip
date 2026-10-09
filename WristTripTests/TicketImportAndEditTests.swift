import Foundation
import UIKit
import XCTest
@testable import WristTrip

final class TicketImportAndEditTests: XCTestCase {
    func testSeparatedStationsAndOvernightArrivalInTicketRegion() {
        let fields = TicketOCRService().parse([
            line("2026年10月08日 出发", 0.2, 0.88),
            line("G1088", 0.5, 0.79),
            line("上海虹桥", 0.18, 0.73),
            line("→", 0.5, 0.73),
            line("南京南", 0.82, 0.73),
            line("22:45", 0.18, 0.68),
            line("02:19", 0.82, 0.68),
            line("历时3小时34分", 0.5, 0.63),
            line("检票口：13A、13B 如有变更，以现场公告为准", 0.5, 0.57),
            line("乘车人", 0.15, 0.43),
            line("06车 12A 二等座", 0.5, 0.38),
            line("下单时间 2026年09月01日", 0.5, 0.23),
            line("杭州酒店 09:00", 0.5, 0.17)
        ])

        XCTAssertEqual(fields.train, "G1088")
        XCTAssertEqual(fields.travelDate, "2026-10-08")
        XCTAssertEqual(fields.from, "上海虹桥")
        XCTAssertEqual(fields.to, "南京南")
        XCTAssertEqual(fields.departureTime, "22:45")
        XCTAssertEqual(fields.arrivalTime, "02:19")
        XCTAssertEqual(fields.arrivalDate, "2026-10-09")
        XCTAssertEqual(fields.gate, "13A、13B")
        XCTAssertEqual(fields.seats.first?.seatClass, "二等座")
    }

    func testAmbiguousLeftStationsRemainEmpty() {
        let fields = TicketOCRService().parse([
            line("G1088", 0.5, 0.75),
            line("上海虹桥", 0.18, 0.71),
            line("北京南", 0.22, 0.69),
            line("→", 0.5, 0.70),
            line("南京南", 0.82, 0.71),
            line("乘车人", 0.5, 0.40)
        ])
        XCTAssertNil(fields.from)
        XCTAssertNil(fields.to)
    }

    func testStationsBelowSeparateTimes() {
        let fields = TicketOCRService().parse([
            line("G8903", 0.50, 0.76),
            line("22:05", 0.16, 0.70),
            line("22:26", 0.82, 0.70),
            line("北京南>", 0.16, 0.59),
            line("经停站", 0.50, 0.64),
            line("廊坊>", 0.82, 0.59),
            line("历时21分", 0.50, 0.53),
            line("发车时间：2026.09.29 星期二", 0.25, 0.44),
            line("检票口13A、13B", 0.50, 0.35),
            line("二等座 11车 01号", 0.68, 0.31),
            line("¥25", 0.76, 0.25)
        ])

        XCTAssertEqual(fields.from, "北京南")
        XCTAssertEqual(fields.to, "廊坊")
        XCTAssertEqual(fields.departureTime, "22:05")
        XCTAssertEqual(fields.arrivalTime, "22:26")
        XCTAssertEqual(fields.travelDate, "2026-09-29")
        XCTAssertEqual(fields.arrivalDate, "2026-09-29")
        XCTAssertEqual(fields.seats.first?.carriage, "11车")
        XCTAssertEqual(fields.seats.first?.seat, "01")
        XCTAssertEqual(fields.seats.first?.seatClass, "二等座")
        XCTAssertEqual(fields.fare, "¥25")
    }

    func testRealOCRStationRowsIgnoreTicketNotice() {
        let fields = TicketOCRService().parse([
            line("下单时间：2026.09.29", 0.82, 0.812),
            line("22:05", 0.166, 0.713),
            line("G8903〉", 0.500, 0.725),
            line("22:26", 0.832, 0.714),
            line("经停站", 0.498, 0.689),
            line("北京南〉", 0.146, 0.664),
            line("廊坊〉", 0.874, 0.664),
            line("历时21分", 0.500, 0.655),
            line("发车时间：2026.09.29 星期二", 0.301, 0.595),
            line("车票当日当次有效", 0.785, 0.595),
            line("检票口13A、13B（如有变更，请以现场公告为准）", 0.399, 0.531),
            line("二等座11车01C号〉", 0.721, 0.344),
            line("¥25［6.3折", 0.827, 0.289)
        ])

        XCTAssertEqual(fields.train, "G8903")
        XCTAssertEqual(fields.from, "北京南")
        XCTAssertEqual(fields.to, "廊坊")
        XCTAssertEqual(fields.travelDate, "2026-09-29")
        XCTAssertEqual(fields.departureTime, "22:05")
        XCTAssertEqual(fields.arrivalTime, "22:26")
        XCTAssertEqual(fields.arrivalDate, "2026-09-29")
        XCTAssertEqual(fields.durationMinutes, 21)
        XCTAssertEqual(fields.gate, "13A、13B")
        XCTAssertEqual(fields.seats.first?.carriage, "11车")
        XCTAssertEqual(fields.seats.first?.seat, "01C")
        XCTAssertEqual(fields.fare, "¥25")
    }

    func testRealOCRSecondStationRow() {
        let fields = TicketOCRService().parse([
            line("下单时间：2026.09.29", 0.825, 0.972),
            line("07:16", 0.159, 0.854),
            line("G6746〉", 0.501, 0.867),
            line("07:37", 0.837, 0.857),
            line("经停站", 0.501, 0.827),
            line("大厂〉", 0.128, 0.795),
            line("北京通州>", 0.842, 0.796),
            line("历时21分", 0.502, 0.786),
            line("发车时间：2026.09.30 星期三", 0.299, 0.714),
            line("车票当日当次有效", 0.791, 0.714),
            line("二等座 02车 18C号〉", 0.692, 0.501),
            line("¥12", 0.788, 0.438)
        ])

        XCTAssertEqual(fields.train, "G6746")
        XCTAssertEqual(fields.from, "大厂")
        XCTAssertEqual(fields.to, "北京通州")
        XCTAssertEqual(fields.travelDate, "2026-09-30")
        XCTAssertEqual(fields.departureTime, "07:16")
        XCTAssertEqual(fields.arrivalTime, "07:37")
        XCTAssertEqual(fields.arrivalDate, "2026-09-30")
        XCTAssertEqual(fields.durationMinutes, 21)
        XCTAssertNil(fields.gate)
        XCTAssertEqual(fields.seats.first?.carriage, "02车")
        XCTAssertEqual(fields.seats.first?.seat, "18C")
        XCTAssertEqual(fields.fare, "¥12")
    }

    func testSecondOrderCardStationsBelowSeparateTimes() {
        let fields = TicketOCRService().parse([
            line("G6746", 0.50, 0.76),
            line("07:16", 0.16, 0.70),
            line("07:37", 0.82, 0.70),
            line("大厂 ›", 0.16, 0.59),
            line("经停站", 0.50, 0.64),
            line("北京通州 ›", 0.82, 0.59),
            line("历时21分", 0.50, 0.53),
            line("发车时间：2026.09.30 星期三", 0.25, 0.44),
            line("二等座 02车 18C号", 0.68, 0.36),
            line("¥12", 0.76, 0.30)
        ])

        XCTAssertEqual(fields.from, "大厂")
        XCTAssertEqual(fields.to, "北京通州")
        XCTAssertEqual(fields.departureTime, "07:16")
        XCTAssertEqual(fields.arrivalTime, "07:37")
        XCTAssertEqual(fields.travelDate, "2026-09-30")
        XCTAssertEqual(fields.arrivalDate, "2026-09-30")
        XCTAssertEqual(fields.seats.first?.carriage, "02车")
        XCTAssertEqual(fields.seats.first?.seat, "18C")
        XCTAssertEqual(fields.seats.first?.seatClass, "二等座")
        XCTAssertEqual(fields.fare, "¥12")
    }

    func testStationsBelowTimesWhenOCRSplitsStationCharacters() {
        let fields = TicketOCRService().parse([
            line("G8903", 0.50, 0.76),
            line("22:05", 0.16, 0.70),
            line("22:26", 0.82, 0.70),
            line("北 京 南", 0.16, 0.59),
            line(">", 0.24, 0.59),
            line("廊 坊", 0.82, 0.59),
            line(">", 0.90, 0.59),
            line("历时21分", 0.50, 0.53),
            line("发车时间：2026.09.29 星期二", 0.25, 0.44)
        ])

        XCTAssertEqual(fields.from, "北京南")
        XCTAssertEqual(fields.to, "廊坊")
    }

    func testArrivalStationIgnoresNearbyStopLabel() {
        let fields = TicketOCRService().parse([
            line("G8903", 0.50, 0.76),
            line("22:05", 0.16, 0.70),
            line("22:26", 0.82, 0.70),
            line("经停站", 0.82, 0.65),
            line("北京南", 0.16, 0.59),
            line("廊坊", 0.82, 0.59)
        ])

        XCTAssertEqual(fields.from, "北京南")
        XCTAssertEqual(fields.to, "廊坊")
    }

    func testStationNameEndingInStationIsPreserved() {
        let fields = TicketOCRService().parse([
            line("G8903", 0.50, 0.76),
            line("22:05", 0.16, 0.70),
            line("22:26", 0.82, 0.70),
            line("北京南", 0.16, 0.59),
            line("清河站", 0.82, 0.59)
        ])

        XCTAssertEqual(fields.to, "清河站")
    }

    func testEditedScheduleAndSeatClassUpdateMetadata() throws {
        let original = Ticket(id: UUID(), train: "G1088", date: "2026-10-08", departTime: "22:45",
                              arriveTime: "02:19", from: "上海虹桥", to: "南京南", carriage: "06车",
                              seat: "12A", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                              syncText: "尚未同步", plannedDepartureAt: Ticket.scheduleDate(day: "2026-10-08", time: "22:45"),
                              plannedArrivalAt: Ticket.scheduleDate(day: "2026-10-09", time: "02:19"))
        var fields = TicketEditFields(ticket: original)
        fields.departureTime = "23:45"
        fields.arrivalTime = "03:19"
        fields.seatClass = "二等座"
        fields.fare = "¥25"
        let now = Ticket.scheduleDate(day: "2026-10-08", time: "23:30")!
        let edited = try fields.updatedTicket(from: original, now: now).get()

        XCTAssertEqual(edited.durationMinutes, 214)
        XCTAssertEqual(edited.plannedDepartureAt, Ticket.scheduleDate(day: "2026-10-08", time: "23:45"))
        XCTAssertEqual(edited.plannedArrivalAt, Ticket.scheduleDate(day: "2026-10-09", time: "03:19"))
        XCTAssertEqual(edited.status, .boarding)
        XCTAssertEqual(edited.fieldSources["departureTime"], .manual)
        XCTAssertEqual(edited.fieldSources["seatClass"], .manual)
        XCTAssertEqual(edited.fieldSources["fare"], .manual)
        XCTAssertEqual(edited.updatedAt, now)
        XCTAssertEqual(edited.seatClass, "二等座")
        XCTAssertEqual(edited.fare, "¥25")
    }

    func testLegacyStoredTicketDecodesWithoutSeatClass() throws {
        let ticket = Ticket(id: UUID(), train: "G1", date: "2026-10-08", departTime: "08:00",
                            arriveTime: "09:00", from: "北京南", to: "天津南", carriage: "01车",
                            seat: "01A", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                            syncText: "尚未同步")
        let encoded = try JSONEncoder().encode(ticket)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "seatClass")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(Ticket.self, from: legacy).seatClass, "")
    }

    func testEditingSeatPreservesOCRDurationWithoutArrivalDate() throws {
        let original = Ticket(id: UUID(), train: "G1", date: "2026-10-08", departTime: "08:00",
                              arriveTime: "", from: "北京南", to: "天津南", carriage: "",
                              seat: "", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                              syncText: "草稿", plannedDepartureAt: Ticket.scheduleDate(day: "2026-10-08", time: "08:00"),
                              durationMinutes: 38)
        var fields = TicketEditFields(ticket: original)
        fields.seat = "01A"
        let edited = try fields.updatedTicket(from: original).get()
        XCTAssertEqual(edited.durationMinutes, 38)
        XCTAssertNil(edited.plannedArrivalAt)
    }

    func testOrderNumberIsReadFromLabeledLine() {
        let fields = TicketOCRService().parse([
            line("G1088", 0.5, 0.75),
            line("订单号：E123456789", 0.5, 0.20)
        ])
        XCTAssertEqual(fields.orderNumber, "E123456789")
    }

    func testProvidedOrderDetailScreenshotOCRLines() {
        let fields = TicketOCRService().parse([
            line("订单详情", 0.497, 0.917),
            line("订单号：EN35012368", 0.167, 0.876),
            line("下单时间：2026.09.29", 0.822, 0.876),
            line("22:05", 0.165, 0.814),
            line("G8903〉", 0.500, 0.821),
            line("22:26", 0.830, 0.814),
            line("北京南〉", 0.145, 0.784),
            line("经停站", 0.498, 0.798),
            line("廊坊〉", 0.874, 0.784),
            line("历时21分", 0.502, 0.778),
            line("发车时间：2026.09.29 星期二", 0.296, 0.739),
            line("车票当日当次有效", 0.788, 0.740),
            line("检票口13A、13B（如有变更，请以现场公告为准）", 0.398, 0.699)
        ])

        XCTAssertEqual(fields.orderNumber, "EN35012368")
        XCTAssertEqual(fields.train, "G8903")
        XCTAssertEqual(fields.travelDate, "2026-09-29")
        XCTAssertEqual(fields.departureTime, "22:05")
        XCTAssertEqual(fields.arrivalTime, "22:26")
        XCTAssertEqual(fields.from, "北京南")
        XCTAssertEqual(fields.to, "廊坊")
        XCTAssertEqual(fields.gate, "13A、13B")
    }

    func testOrderNumberBesideUpperLeftLabel() {
        let fields = TicketOCRService().parse([
            line("订单号", 0.12, 0.95),
            line("E123456789", 0.84, 0.95),
            line("G1088", 0.5, 0.75)
        ])
        XCTAssertEqual(fields.orderNumber, "E123456789")
    }

    func testOrderNumberWithFullWidthCharactersAndSeparatedLabel() {
        let fields = TicketOCRService().parse([
            line("订 单 编 号：Ｅ１２３４５６７８９", 0.32, 0.95),
            line("G1088", 0.5, 0.75)
        ])
        XCTAssertEqual(fields.orderNumber, "E123456789")
    }

    func testOrderNumberAboveLabelAndBeforeTrain() {
        let fields = TicketOCRService().parse([
            line("E123456789", 0.36, 0.96),
            line("订单号码", 0.12, 0.92),
            line("G1088", 0.5, 0.75)
        ])
        XCTAssertEqual(fields.orderNumber, "E123456789")
    }

    func testOrderNumberBelowUpperLeftLabel() {
        let fields = TicketOCRService().parse([
            line("订单号：", 0.12, 0.95),
            line("E123456789", 0.26, 0.82),
            line("G1088", 0.5, 0.70)
        ])
        XCTAssertEqual(fields.orderNumber, "E123456789")
    }

    func testOrderNumberRecognizedFromImage() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
            let style: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            ("订单号：" as NSString).draw(at: CGPoint(x: 45, y: 65), withAttributes: style)
            ("EN35012368" as NSString).draw(at: CGPoint(x: 45, y: 133), withAttributes: style)
            ("G1088" as NSString).draw(at: CGPoint(x: 510, y: 480), withAttributes: style)
        }

        let fields = try await TicketOCRService().recognizeFields(in: image)
        XCTAssertEqual(fields.orderNumber, "EN35012368")
    }

    func testOrderNumberKeepsEntireLongValue() {
        let service = TicketOCRService()
        let valid = service.parse([
            line("订单号：E1234567890123456", 0.5, 0.95),
            line("G1088", 0.5, 0.75)
        ])
        let tooLong = service.parse([
            line("订单号：E12345678901234567", 0.5, 0.95),
            line("G1088", 0.5, 0.75)
        ])
        XCTAssertEqual(valid.orderNumber, "E1234567890123456")
        XCTAssertNil(tooLong.orderNumber)
    }

    func testOrderNumberDoesNotUseNearbyPhoneOrAmbiguousValues() {
        let service = TicketOCRService()
        let phone = service.parse([
            line("订单号", 0.12, 0.95),
            line("13812345678", 0.36, 0.95),
            line("G1088", 0.5, 0.75)
        ])
        let ambiguous = service.parse([
            line("订单号", 0.12, 0.95),
            line("E123456789", 0.36, 0.95),
            line("E987654321", 0.36, 0.91),
            line("G1088", 0.5, 0.75)
        ])
        XCTAssertNil(phone.orderNumber)
        XCTAssertNil(ambiguous.orderNumber)
    }

    @MainActor
    func testDuplicateImportUsesOrderNumberAndFallsBackForLegacyTicket() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TripStore(defaults: defaults)
        let departure = Ticket.scheduleDate(day: "2026-10-08", time: "08:00")!
        let existing = Ticket(id: UUID(), train: "G1088", date: "2026-10-08", departTime: "08:00",
                              arriveTime: "09:00", from: "北京南", to: "天津南", carriage: "01车",
                              seat: "01A", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                              syncText: "尚未同步", plannedDepartureAt: departure, orderNumber: "E123456789")
        store.add(existing)

        let sameOrder = Ticket(id: UUID(), train: "G1088", date: "2026-10-08", departTime: "08:00",
                           arriveTime: "09:00", from: "北京南", to: "天津南", carriage: "01车",
                           seat: "01A", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                           syncText: "尚未同步", plannedDepartureAt: departure, orderNumber: "e123456789")
        XCTAssertEqual(store.duplicate(of: sameOrder)?.id, existing.id)

        var differentOrder = sameOrder
        differentOrder.orderNumber = "E987654321"
        XCTAssertNil(store.duplicate(of: differentOrder))

        var legacy = sameOrder
        legacy.orderNumber = ""
        XCTAssertEqual(store.duplicate(of: legacy)?.id, existing.id)
    }

    func testLegacyStoredTicketDecodesWithoutOrderNumber() throws {
        let ticket = Ticket(id: UUID(), train: "G1", date: "2026-10-08", departTime: "08:00",
                            arriveTime: "09:00", from: "北京南", to: "天津南", carriage: "01车",
                            seat: "01A", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                            syncText: "尚未同步")
        let encoded = try JSONEncoder().encode(ticket)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "orderNumber")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(Ticket.self, from: legacy).orderNumber, "")
    }

    @MainActor
    func testArrivalMovesPinnedJourneyToHistoryAndSelectsNextActivity() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TripStore(defaults: defaults)
        let departureA = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrivalA = Ticket.scheduleDate(day: "2026-10-09", time: "09:00")!
        let departureB = Ticket.scheduleDate(day: "2026-10-09", time: "09:20")!
        let arrivalB = Ticket.scheduleDate(day: "2026-10-09", time: "10:00")!
        let first = Ticket(id: UUID(), train: "G1", date: "2026-10-09", departTime: "08:00",
                           arriveTime: "09:00", from: "北京南", to: "天津南", carriage: "01车",
                           seat: "01A", waitingRoom: "待公布", gate: "待公布", status: .onboard,
                           syncText: "已同步", plannedDepartureAt: departureA, plannedArrivalAt: arrivalA)
        let second = Ticket(id: UUID(), train: "G2", date: "2026-10-09", departTime: "09:20",
                            arriveTime: "10:00", from: "天津南", to: "济南西", carriage: "02车",
                            seat: "02A", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                            syncText: "已同步", plannedDepartureAt: departureB, plannedArrivalAt: arrivalB)
        store.add(first)
        store.add(second)
        store.selectForWatch(id: first.id)

        XCTAssertEqual(store.currentTicket(at: arrivalA.addingTimeInterval(-1))?.id, first.id)
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: store.tickets, selectedTicketID: first.id,
                                                               now: arrivalA.addingTimeInterval(-1))?.id, first.id)

        XCTAssertEqual(first.status(at: arrivalA), .arrived)
        store.refreshStatuses(at: arrivalA)
        XCTAssertEqual(store.tickets.first { $0.id == first.id }?.status, .arrived)
        XCTAssertEqual(TripStore(defaults: defaults).tickets.first { $0.id == first.id }?.status, .arrived)
        XCTAssertEqual(store.currentTicket(at: arrivalA)?.id, second.id)
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: store.tickets, selectedTicketID: first.id,
                                                               now: arrivalA)?.id, second.id)
    }

    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> OCRLine {
        OCRLine(text: text, x: x, y: y)
    }
}
