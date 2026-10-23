import Foundation
import UIKit
import XCTest
@testable import WristTrip

final class TicketImportAndEditTests: XCTestCase {
    func testTicketOnsiteLongValueIsPreservedForHorizontalScrolling() {
        let value = "东候车区 12 号候车室（进站后请沿南侧通道前往）"
        XCTAssertEqual(TicketOnsiteDisplayValue(value).text, value)
        XCTAssertEqual(TicketOnsiteDisplayValue("   ").text, "暂未获取到实时检票信息")
    }

    func testTicketOnsiteMarqueeScrollsOnlyWhenContentExceedsFieldWidth() {
        XCTAssertFalse(TicketOnsiteMarqueeBehavior.shouldScroll(contentWidth: 120, viewportWidth: 120))
        XCTAssertFalse(TicketOnsiteMarqueeBehavior.shouldScroll(contentWidth: 96, viewportWidth: 120))
        XCTAssertTrue(TicketOnsiteMarqueeBehavior.shouldScroll(contentWidth: 121, viewportWidth: 120))
        XCTAssertEqual(TicketOnsiteMarqueeBehavior.cycleDistance(contentWidth: 121), 149)
    }

    func testLiveActivityOnsiteFieldsKeepFixedSize() {
        XCTAssertEqual(ActivityOnsiteFieldLayout.fieldHeight, 18)
    }

    func testSmartStackOnsiteFieldsKeepFixedSize() {
        XCTAssertEqual(ActivityOnsiteFieldLayout.fieldHeight, 18)
        XCTAssertEqual(ActivityOnsiteFieldLayout.columnWidth(containerWidth: 200), 89,
                       accuracy: 0.001)
        XCTAssertEqual(ActivityOnsiteFieldLayout.columnWidth(containerWidth: 162), 71,
                       accuracy: 0.001)
    }

    func testScheduleInputFormatsAsDigitsArrive() {
        var date = ""
        let dateExpected = ["2", "20", "202", "2026", "2026-1", "2026-10", "2026-10-2", "2026-10-21"]
        for (digit, expected) in zip("20261021", dateExpected) {
            let result = ScheduleInputFormatter.editedText(
                current: date,
                range: NSRange(location: date.utf16.count, length: 0),
                replacement: String(digit),
                kind: .date)
            date = result.text
            XCTAssertEqual(date, expected)
        }

        var time = ""
        let timeExpected = ["1", "17", "17:4", "17:48"]
        for (digit, expected) in zip("1748", timeExpected) {
            let result = ScheduleInputFormatter.editedText(
                current: time,
                range: NSRange(location: time.utf16.count, length: 0),
                replacement: String(digit),
                kind: .time)
            time = result.text
            XCTAssertEqual(time, expected)
        }
    }

    func testScheduleInputNormalizesPasteAndKeepsDeletionCursor() {
        let pastedDate = ScheduleInputFormatter.editedText(
            current: "",
            range: NSRange(location: 0, length: 0),
            replacement: "2026-10-21",
            kind: .date)
        XCTAssertEqual(pastedDate.text, "2026-10-21")
        XCTAssertEqual(pastedDate.cursorPosition, 10)

        let clippedTime = ScheduleInputFormatter.editedText(
            current: "",
            range: NSRange(location: 0, length: 0),
            replacement: "17:4899",
            kind: .time)
        XCTAssertEqual(clippedTime.text, "17:48")
        XCTAssertEqual(clippedTime.cursorPosition, 5)

        let afterSeparator = ScheduleInputFormatter.editedText(
            current: "17:48",
            range: NSRange(location: 2, length: 1),
            replacement: "",
            kind: .time,
            backspaceOverSeparator: true)
        XCTAssertEqual(afterSeparator.text, "14:8")
        XCTAssertEqual(afterSeparator.cursorPosition, 1)

        let afterLastDigit = ScheduleInputFormatter.editedText(
            current: "17:48",
            range: NSRange(location: 4, length: 1),
            replacement: "",
            kind: .time)
        XCTAssertEqual(afterLastDigit.text, "17:4")
        XCTAssertEqual(afterLastDigit.cursorPosition, 4)
    }

    func testActivityPushTokenUsesLowercaseHexAndReferenceDateEncoding() throws {
        let data = Data([0x00, 0xab, 0xff])
        XCTAssertEqual(ActivityPushTokenService.hexToken(data), "00abff")

        let instant = Date(timeIntervalSinceReferenceDate: 123.25)
        let encoded = try JSONEncoder().encode(["createdAt": instant])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(object["createdAt"] as? Double), 123.25, accuracy: 0.0001)
    }

    func testScheduleResponseRequiresBusinessSuccessCode() throws {
        let success = try JSONDecoder().decode(ActivityPushTokenService.ScheduleResponse.self,
                                                from: Data(#"{"code":0,"data":12,"err":""}"#.utf8))
        XCTAssertEqual(success.code, 0)
        XCTAssertEqual(success.data, 12)
        XCTAssertTrue(success.confirmsSnapshotSaved(httpStatus: 200))
        XCTAssertFalse(success.confirmsSnapshotSaved(httpStatus: 201))

        let rejected = try JSONDecoder().decode(ActivityPushTokenService.ScheduleResponse.self,
                                                  from: Data(#"{"code":114,"data":null,"err":"unauthorized"}"#.utf8))
        XCTAssertEqual(rejected.code, 114)
        XCTAssertEqual(rejected.err, "unauthorized")
        XCTAssertFalse(rejected.confirmsSnapshotSaved(httpStatus: 200))

        let missingVersion = try JSONDecoder().decode(ActivityPushTokenService.ScheduleResponse.self,
            from: Data(#"{"code":0,"data":null,"err":""}"#.utf8))
        XCTAssertFalse(missingVersion.confirmsSnapshotSaved(httpStatus: 200))

        for version in [0, -1] {
            let response = try JSONDecoder().decode(ActivityPushTokenService.ScheduleResponse.self,
                from: Data("{\"code\":0,\"data\":\(version)}".utf8))
            XCTAssertFalse(response.confirmsSnapshotSaved(httpStatus: 200))
        }
    }

    func testAccessTokenExchangeContract() throws {
        let scheduleURL = try XCTUnwrap(URL(string: "https://api.clenson.com/api/activity-schedules"))
        XCTAssertEqual(ActivityPushTokenService.exchangeURL(for: scheduleURL)?.absoluteString,
                       "https://api.clenson.com/api/auth/token/exchange")

        let response = try JSONDecoder().decode(ActivityPushTokenService.ExchangeResponse.self,
            from: Data(#"{"code":0,"data":{"accessToken":"server-issued","tokenType":"Bearer","expiresIn":2592000},"err":""}"#.utf8))
        XCTAssertEqual(response.code, 0)
        XCTAssertEqual(response.data?.accessToken, "server-issued")
        XCTAssertEqual(response.data?.expiresIn, 2_592_000)

        let credential = ActivityPushTokenService.AccessCredential(
            accessToken: "server-issued", expiresAt: Date(timeIntervalSinceReferenceDate: 1000))
        XCTAssertTrue(credential.isValid(at: Date(timeIntervalSinceReferenceDate: 900)))
        XCTAssertFalse(credential.isValid(at: Date(timeIntervalSinceReferenceDate: 950)))
    }

    func testAnonymousCredentialSurvivesExpiryForRenewal() throws {
        let expiresAt = Date(timeIntervalSinceReferenceDate: 100_000)
        let credential = ActivityPushTokenService.AccessCredential(
            accessToken: "anonymous-access", expiresAt: expiresAt, isAnonymous: true)
        let restored = try JSONDecoder().decode(ActivityPushTokenService.AccessCredential.self,
                                                from: JSONEncoder().encode(credential))
        XCTAssertTrue(restored.isAnonymous)
        XCTAssertEqual(restored.accessToken, "anonymous-access")
        XCTAssertTrue(restored.needsRenewal(at: expiresAt.addingTimeInterval(-3600)))
        XCTAssertFalse(restored.needsRenewal(at: expiresAt.addingTimeInterval(-2 * 24 * 3600)))

        let prior = ActivityPushTokenService.AccessCredential(
            accessToken: "prior-anonymous", expiresAt: expiresAt.addingTimeInterval(-3600),
            isAnonymous: true)
        let stored = ActivityPushTokenService.StoredCredentials(
            current: credential, previousAnonymous: [prior])
        let recovered = try JSONDecoder().decode(ActivityPushTokenService.StoredCredentials.self,
                                                 from: JSONEncoder().encode(stored))
        XCTAssertEqual(recovered.current.accessToken, "anonymous-access")
        XCTAssertEqual(recovered.previousAnonymous.map(\.accessToken), ["prior-anonymous"])

        let legacy = try JSONDecoder().decode(ActivityPushTokenService.AccessCredential.self,
            from: Data(#"{"accessToken":"existing-user","expiresAt":100000}"#.utf8))
        XCTAssertFalse(legacy.isAnonymous)
    }

    func testCompleteScheduleSnapshotUsesReferenceDatesAndExplicitNulls() throws {
        let departure = Date(timeIntervalSinceReferenceDate: 820_454_400)
        let arrival = Date(timeIntervalSinceReferenceDate: 820_454_700)
        let ticket = Ticket(id: UUID(), train: "G8903", date: "2027-01-01", departTime: "08:00",
                            arriveTime: "08:05", from: "北京南", to: "廊坊", carriage: "11车", seat: "01C",
                            waitingRoom: "", gate: "13A", status: .upcoming, syncText: "",
                            plannedDepartureAt: departure, plannedArrivalAt: arrival)
        let scheduled = try XCTUnwrap(ActivityPushTokenService.ScheduledTicket(ticket, now: departure))
        let createdAt = Date(timeIntervalSinceReferenceDate: 820_454_123.25)
        let registration = ActivityPushTokenService.Registration(
            kind: .activity, token: "token", activityID: "activity-1", ticketID: ticket.id,
            createdAt: createdAt, departureAt: departure)
        let snapshot = ActivityPushTokenService.ScheduleSnapshot(
            deviceID: UUID(), snapshotVersion: 101, enabled: true, pushToStartToken: nil, selectedTicketID: nil,
            tickets: [scheduled], activityTokens: [registration])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertTrue(object["pushToStartToken"] is NSNull)
        XCTAssertEqual(object["snapshotVersion"] as? Int64, 101)
        XCTAssertTrue(object["selectedTicketID"] is NSNull)
        XCTAssertNil(object["is_deleted"])
        let encodedRegistration = try XCTUnwrap((object["activityTokens"] as? [[String: Any]])?.first)
        XCTAssertEqual(encodedRegistration["createdAt"] as? Double, 820_454_123.25)
        XCTAssertEqual(encodedRegistration["departureAt"] as? Double, 820_454_400)
        XCTAssertNil(encodedRegistration["is_deleted"])
        let encodedTicket = try XCTUnwrap((object["tickets"] as? [[String: Any]])?.first)
        XCTAssertEqual(encodedTicket["departureAt"] as? Double, 820_454_400)
        XCTAssertEqual(encodedTicket["arrivalAt"] as? Double, 820_454_700)
        XCTAssertEqual(encodedTicket["startAt"] as? Double, 820_443_600)
        XCTAssertNil(encodedTicket["is_deleted"])

        let endpoint = try XCTUnwrap(URL(string: "https://api.clenson.com/api/activity-schedules"))
        let request = try ActivityPushTokenService.scheduleRequest(
            for: snapshot, endpoint: endpoint, accessToken: "test-access-token")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try JSONDecoder().decode(ActivityPushTokenService.ScheduleSnapshot.self,
                                                from: body), snapshot)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("test-access-token"))

        let enabled = ActivityPushTokenService.ScheduleSnapshot(
            deviceID: snapshot.deviceID, snapshotVersion: 102, enabled: true, pushToStartToken: "aabb",
            selectedTicketID: ticket.id, tickets: [scheduled], activityTokens: [])
        let enabledBody = try XCTUnwrap(ActivityPushTokenService.scheduleRequest(
            for: enabled, endpoint: endpoint, accessToken: "test-access-token").httpBody)
        XCTAssertEqual(try JSONDecoder().decode(ActivityPushTokenService.ScheduleSnapshot.self,
                                                from: enabledBody), enabled)

        let disabled = ActivityPushTokenService.ScheduleSnapshot(
            deviceID: snapshot.deviceID, snapshotVersion: 103, enabled: false, pushToStartToken: nil,
            selectedTicketID: nil, tickets: [], activityTokens: [])
        let disabledObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(disabled)) as? [String: Any])
        XCTAssertEqual(disabledObject["enabled"] as? Bool, false)
        XCTAssertTrue(disabledObject["pushToStartToken"] is NSNull)
        XCTAssertEqual((disabledObject["tickets"] as? [Any])?.count, 0)
        XCTAssertEqual((disabledObject["activityTokens"] as? [Any])?.count, 0)
    }

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

    func testLegacyStoredTicketDecodesAndIgnoresRemovedReminderFields() throws {
        let ticket = Ticket(id: UUID(), train: "G1", date: "2026-10-08", departTime: "08:00",
                            arriveTime: "09:00", from: "北京南", to: "天津南", carriage: "01车",
                            seat: "01A", waitingRoom: "待公布", gate: "待公布", status: .upcoming,
                            syncText: "尚未同步")
        let encoded = try JSONEncoder().encode(ticket)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "orderNumber")
        object["activityLeadHours"] = 5
        object["activityReminderEnabled"] = true
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Ticket.self, from: legacy)
        XCTAssertEqual(decoded.orderNumber, "")
        let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNil(roundTrip["activityLeadHours"])
        XCTAssertNil(roundTrip["activityReminderEnabled"])
    }

    func testActivityWindowUsesFixedThreeHourDefault() {
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "22:05")!
        let arrival = Ticket.scheduleDate(day: "2026-10-09", time: "22:26")!
        let ticket = Ticket(id: UUID(), train: "G8903", date: "2026-10-09", departTime: "22:05",
                            arriveTime: "22:26", from: "北京南", to: "廊坊", carriage: "11车",
                            seat: "01C", waitingRoom: "待公布", gate: "13A、13B", status: .upcoming,
                            syncText: "", plannedDepartureAt: departure, plannedArrivalAt: arrival)
        let fiveHoursBefore = departure.addingTimeInterval(-5 * 60 * 60)
        let threeHoursBefore = departure.addingTimeInterval(-3 * 60 * 60)

        XCTAssertEqual(ticket.startAt, threeHoursBefore)
        XCTAssertNil(TripActivityService.ticketForActivity(tickets: [ticket], selectedTicketID: ticket.id,
                                                             now: fiveHoursBefore))
        XCTAssertEqual(ticket.startAt, threeHoursBefore)
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: [ticket], selectedTicketID: ticket.id,
                                                               requestedTicketID: ticket.id,
                                                               now: fiveHoursBefore)?.id, ticket.id)
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: [ticket], selectedTicketID: ticket.id,
                                                               manualActivityTicketID: ticket.id,
                                                               manualActivityStartedAt: fiveHoursBefore,
                                                               now: fiveHoursBefore)?.id, ticket.id)

        let eligibleDeparture = departure.addingTimeInterval(-2 * 60 * 60)
        let eligible = Ticket(id: UUID(), train: "G8902", date: "2026-10-09", departTime: "20:05",
                              arriveTime: "20:26", from: "北京南", to: "廊坊", carriage: "11车",
                              seat: "02C", waitingRoom: "待公布", gate: "13A、13B", status: .upcoming,
                              syncText: "", plannedDepartureAt: eligibleDeparture,
                              plannedArrivalAt: departure.addingTimeInterval(-90 * 60))
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: [eligible, ticket],
                                                               selectedTicketID: eligible.id,
                                                               requestedTicketID: ticket.id,
                                                               now: fiveHoursBefore)?.id, ticket.id)

        let longArrival = departure.addingTimeInterval(12 * 60 * 60)
        let longTicket = Ticket(id: UUID(), train: "G8904", date: "2026-10-09", departTime: "22:05",
                                arriveTime: "10:05", from: "北京南", to: "上海虹桥", carriage: "11车",
                                seat: "03C", waitingRoom: "待公布", gate: "13A", status: .upcoming,
                                syncText: "", plannedDepartureAt: departure, plannedArrivalAt: longArrival)
        let afterManualLimit = fiveHoursBefore.addingTimeInterval(8 * 60 * 60)
        XCTAssertNil(TripActivityService.ticketForActivity(tickets: [longTicket],
                                                             selectedTicketID: longTicket.id,
                                                             manualActivityTicketID: longTicket.id,
                                                             manualActivityStartedAt: fiveHoursBefore,
                                                             now: afterManualLimit))
        XCTAssertNil(TripActivityService.manualActivityEndReason(startedAt: fiveHoursBefore,
                                                                  arrivalAt: longArrival,
                                                                  now: afterManualLimit.addingTimeInterval(-1)))
        XCTAssertEqual(TripActivityService.manualActivityEndReason(startedAt: fiveHoursBefore,
                                                                    arrivalAt: longArrival,
                                                                    now: afterManualLimit), .timeLimitReached)
        XCTAssertNil(TripActivityService.manualActivityEndReason(startedAt: afterManualLimit,
                                                                  arrivalAt: longArrival,
                                                                  now: afterManualLimit))
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: [longTicket],
                                                               selectedTicketID: longTicket.id,
                                                               manualActivityTicketID: longTicket.id,
                                                               manualActivityStartedAt: afterManualLimit,
                                                               now: afterManualLimit)?.id, longTicket.id)
        XCTAssertEqual(TripActivityService.manualActivityEndReason(startedAt: fiveHoursBefore,
                                                                    arrivalAt: afterManualLimit,
                                                                    now: afterManualLimit), .arrived)
    }

    func testAutomaticActivityCandidateUsesEarliestOngoingThenNearestUpcoming() {
        let now = Date(timeIntervalSinceReferenceDate: 820_454_400)
        let ongoingFirst = scheduledTicket(departure: now.addingTimeInterval(-3600),
                                           arrival: now.addingTimeInterval(600))
        let ongoingSecond = scheduledTicket(departure: now.addingTimeInterval(-900),
                                            arrival: now.addingTimeInterval(3600))
        let upcoming = scheduledTicket(departure: now.addingTimeInterval(1800),
                                       arrival: now.addingTimeInterval(7200))

        XCTAssertEqual(TripActivityService.ticketForActivity(
            tickets: [upcoming, ongoingSecond, ongoingFirst], selectedTicketID: ongoingSecond.id,
            now: now)?.id, ongoingFirst.id)
        XCTAssertEqual(TripActivityService.ticketForActivity(
            tickets: [upcoming, ongoingFirst], selectedTicketID: ongoingFirst.id,
            now: ongoingFirst.plannedArrivalAt!)?.id, upcoming.id)
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
        XCTAssertEqual(store.selectedTicketID, second.id)
        XCTAssertEqual(TripStore(defaults: defaults).selectedTicketID, second.id)
        XCTAssertEqual(store.currentTicket(at: arrivalA)?.id, second.id)
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: store.tickets, selectedTicketID: first.id,
                                                               now: arrivalA)?.id, second.id)
    }

    @MainActor
    func testBackgroundRefreshPersistsEveryBoundaryBeforeUpdatingDisplays() async throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = departure.addingTimeInterval(60 * 60)
        let first = scheduledTicket(departure: departure, arrival: arrival)
        let next = scheduledTicket(departure: arrival.addingTimeInterval(20 * 60),
                                   arrival: arrival.addingTimeInterval(60 * 60))
        let store = TripStore(defaults: defaults)
        store.add(first)
        store.add(next)
        store.selectForWatch(id: first.id)

        for (now, expected) in [(first.startAt!, TicketStatus.upcoming),
                                (departure.addingTimeInterval(-2 * 60 * 60), .upcoming),
                                (departure.addingTimeInterval(-60 * 60), .upcoming),
                                (departure.addingTimeInterval(-30 * 60), .boarding),
                                (departure, .onboard),
                                (departure.addingTimeInterval(30 * 60), .onboard),
                                (arrival, .arrived)] {
            var activityCalled = false
            var watchCalled = false
            let success = await TripBackgroundRefreshService.refresh(now: now, defaults: defaults) { tickets, selectedID, instant, enabled in
                activityCalled = true
                XCTAssertEqual(instant, now)
                XCTAssertTrue(enabled)
                XCTAssertEqual(tickets.first { $0.id == first.id }?.status, expected)
                let persisted = TripStore(defaults: defaults)
                XCTAssertEqual(persisted.tickets.first { $0.id == first.id }?.status, expected)
                let chosen = TripActivityService.ticketForActivity(tickets: tickets, selectedTicketID: selectedID, now: now)
                XCTAssertEqual(chosen?.id, now == arrival ? next.id : first.id)
            } syncWatch: { tickets, selectedID in
                watchCalled = true
                XCTAssertEqual(tickets.first { $0.id == first.id }?.status, expected)
                if now == arrival { XCTAssertEqual(selectedID, next.id) }
                return true
            }
            XCTAssertTrue(success)
            XCTAssertTrue(activityCalled)
            XCTAssertTrue(watchCalled)
        }
    }

    @MainActor
    func testBackgroundRefreshHonorsSwitchAndSyncsAfterActivityFailure() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "wristTrip.liveActivitiesEnabled")
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = departure.addingTimeInterval(60 * 60)
        TripStore(defaults: defaults).add(scheduledTicket(departure: departure, arrival: arrival))
        var queued = false
        let success = await TripBackgroundRefreshService.refresh(now: arrival, defaults: defaults) { _, _, _, enabled in
            XCTAssertFalse(enabled)
            throw NSError(domain: "ActivityRefreshTest", code: 1)
        } syncWatch: { tickets, _ in
            queued = true
            XCTAssertEqual(tickets.first?.status, .arrived)
            return true
        }
        XCTAssertFalse(success)
        XCTAssertTrue(queued)
        XCTAssertEqual(TripStore(defaults: defaults).tickets.first?.status, .arrived)
    }

    @MainActor
    func testDelayedArrivalRefreshClearsSelectionAndPublishesArrivedTicket() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = departure.addingTimeInterval(60 * 60)
        let ticket = scheduledTicket(departure: departure, arrival: arrival)
        let store = TripStore(defaults: defaults)
        store.add(ticket)
        store.selectForWatch(id: ticket.id)
        let lateWake = arrival.addingTimeInterval(20 * 60)

        let success = await TripBackgroundRefreshService.refresh(now: lateWake, defaults: defaults) { tickets, selectedID, _, enabled in
            XCTAssertTrue(enabled)
            XCTAssertEqual(tickets.first?.status, .arrived)
            XCTAssertNil(selectedID)
            XCTAssertNil(TripActivityService.ticketForActivity(tickets: tickets, selectedTicketID: selectedID, now: lateWake))
        } syncWatch: { tickets, selectedID in
            XCTAssertEqual(tickets.first?.status, .arrived)
            XCTAssertNil(selectedID)
            return true
        }

        XCTAssertTrue(success)
        XCTAssertEqual(TripStore(defaults: defaults).tickets.first?.status, .arrived)
        XCTAssertNil(TripStore(defaults: defaults).selectedTicketID)
        XCTAssertEqual(TripBackgroundRefreshService.nextRequestDate(tickets: [ticket], after: lateWake,
                                                                    retryAfterFailure: true),
                       lateWake.addingTimeInterval(15 * 60))
    }

    @MainActor
    func testRefreshBoundariesAdvanceThroughWindowDepartureAndArrival() {
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = departure.addingTimeInterval(60 * 60)
        let ticket = scheduledTicket(departure: departure, arrival: arrival)
        let start = ticket.startAt!
        let twoHoursBefore = departure.addingTimeInterval(-2 * 60 * 60)
        let oneHourBefore = departure.addingTimeInterval(-60 * 60)
        let boarding = departure.addingTimeInterval(-30 * 60)
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [ticket], after: start.addingTimeInterval(-1)), start)
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [ticket], after: start), twoHoursBefore)
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [ticket], after: twoHoursBefore), oneHourBefore)
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [ticket], after: oneHourBefore), boarding)
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [ticket], after: boarding), departure)
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [ticket], after: departure), arrival)
        XCTAssertNil(TripBackgroundRefreshService.nextBoundary(tickets: [ticket], after: arrival))
        let longArrival = departure.addingTimeInterval(12 * 60 * 60)
        let longTicket = scheduledTicket(departure: departure, arrival: longArrival)
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [longTicket], after: departure),
                       longTicket.startAt?.addingTimeInterval(8 * 60 * 60))
        let edited = scheduledTicket(departure: departure.addingTimeInterval(60 * 60), arrival: arrival.addingTimeInterval(60 * 60))
        XCTAssertEqual(TripBackgroundRefreshService.nextBoundary(tickets: [edited], after: departure),
                       edited.plannedDepartureAt?.addingTimeInterval(-30 * 60))
    }

    @MainActor
    func testArrivalClearsWatchSelectionWhenThereIsNoNextJourney() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TripStore(defaults: defaults)
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = Ticket.scheduleDate(day: "2026-10-09", time: "09:00")!
        let ticket = scheduledTicket(departure: departure, arrival: arrival)
        store.add(ticket)
        store.selectForWatch(id: ticket.id)

        XCTAssertTrue(store.refreshStatuses(at: arrival))
        XCTAssertEqual(store.tickets.first?.status, .arrived)
        XCTAssertNil(store.selectedTicketID)

        let persisted = TripStore(defaults: defaults)
        XCTAssertEqual(persisted.tickets.first?.status, .arrived)
        XCTAssertNil(persisted.selectedTicketID)
    }

    @MainActor
    func testSharedScheduleRulesCoverAllBoundariesAndDisplayedLeg() {
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = Ticket.scheduleDate(day: "2026-10-09", time: "12:00")!
        XCTAssertEqual(TripScheduleRules.status(departure: departure, arrival: arrival,
                                                 now: departure.addingTimeInterval(-3 * 60 * 60)), .upcoming)
        XCTAssertEqual(TripScheduleRules.status(departure: departure, arrival: arrival,
                                                 now: departure.addingTimeInterval(-2 * 60 * 60)), .upcoming)
        XCTAssertEqual(TripScheduleRules.status(departure: departure, arrival: arrival,
                                                 now: departure.addingTimeInterval(-30 * 60)), .boarding)
        XCTAssertEqual(TripScheduleRules.status(departure: departure, arrival: arrival,
                                                 now: departure), .onboard)
        XCTAssertEqual(TripScheduleRules.status(departure: departure, arrival: arrival,
                                                 now: arrival), .arrived)

        let before = TripScheduleRules.displayedLeg(departure: departure, arrival: arrival,
                                                     origin: "北京南", destination: "天津南",
                                                     now: departure.addingTimeInterval(-1))
        XCTAssertEqual(before.station, "北京南")
        XCTAssertEqual(before.time, departure)
        let after = TripScheduleRules.displayedLeg(departure: departure, arrival: arrival,
                                                    origin: "北京南", destination: "天津南",
                                                    now: departure)
        XCTAssertEqual(after.station, "天津南")
        XCTAssertEqual(after.time, arrival)
    }

    @MainActor
    func testAutomaticWindowEntryFromOutsideAndInclusiveArrivalBoundary() {
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = departure.addingTimeInterval(60 * 60)
        let windowStart = TripScheduleRules.automaticStart(departure: departure)

        XCTAssertFalse(TripScheduleRules.isWithinAutomaticWindow(
            departure: departure, arrival: arrival, now: windowStart.addingTimeInterval(-1)))
        XCTAssertTrue(TripScheduleRules.isWithinAutomaticWindow(
            departure: departure, arrival: arrival, now: windowStart))
        XCTAssertTrue(TripScheduleRules.isWithinAutomaticWindow(
            departure: departure, arrival: arrival, now: departure))
        XCTAssertFalse(TripScheduleRules.isWithinAutomaticWindow(
            departure: departure, arrival: arrival, now: arrival))
    }

    @MainActor
    func testAdjacentArrivalHandoffSelectsNextJourneyAtExactBoundary() {
        let arrivalA = Ticket.scheduleDate(day: "2026-10-09", time: "09:00")!
        let departureB = arrivalA
        let arrivalB = arrivalA.addingTimeInterval(60 * 60)
        let first = scheduledTicket(departure: arrivalA.addingTimeInterval(-60 * 60), arrival: arrivalA)
        let second = scheduledTicket(departure: departureB, arrival: arrivalB)

        XCTAssertEqual(TripActivityService.ticketForActivity(
            tickets: [first, second], selectedTicketID: first.id, now: arrivalA)?.id, second.id)
        XCTAssertTrue(TripScheduleRules.isWithinAutomaticWindow(
            departure: departureB, arrival: arrivalB, now: arrivalA))
    }

    @MainActor
    func testRemoteArrivalEndDoesNotBecomeUserDismissal() {
        let arrival = Ticket.scheduleDate(day: "2026-10-09", time: "09:00")!
        let ticket = scheduledTicket(departure: arrival.addingTimeInterval(-3600), arrival: arrival)
        let attributes = activityAttributes(for: ticket)

        XCTAssertFalse(TripActivityService.shouldRecordDismissal(
            state: .dismissed, attributes: attributes, programmaticEnd: false,
            tickets: [ticket], now: arrival))
        XCTAssertFalse(TripActivityService.shouldRecordDismissal(
            state: .ended, attributes: attributes, programmaticEnd: false,
            tickets: [ticket], now: arrival.addingTimeInterval(-60)))
        XCTAssertFalse(TripActivityService.shouldRecordDismissal(
            state: .dismissed, attributes: attributes, programmaticEnd: true,
            tickets: [ticket], now: arrival.addingTimeInterval(-60)))
        XCTAssertTrue(TripActivityService.shouldRecordDismissal(
            state: .dismissed, attributes: attributes, programmaticEnd: false,
            tickets: [ticket], now: arrival.addingTimeInterval(-60)))
    }

    @MainActor
    func testDismissalAppliesOnlyToOriginalScheduleAndDiscardsLegacyUUIDMarker() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let original = scheduledTicket(departure: departure, arrival: departure.addingTimeInterval(3600))
        let store = TripStore(defaults: defaults)
        store.add(original)
        defaults.set([original.id.uuidString], forKey: "wristTrip.dismissedActivityTicketIDs")
        XCTAssertEqual(TripActivityService.eligibleTickets([original], defaults: defaults).map(\.id), [original.id])
        XCTAssertNil(defaults.object(forKey: "wristTrip.dismissedActivityTicketIDs"))

        TripActivityService.recordDismissal(attributes: activityAttributes(for: original), defaults: defaults)
        XCTAssertTrue(TripActivityService.eligibleTickets([original], defaults: defaults).isEmpty)
        XCTAssertEqual(TripActivityService.eligibleTickets(
            [original], requestedTicketID: original.id, defaults: defaults).map(\.id), [original.id])
        TripActivityService.recordDismissal(attributes: activityAttributes(for: original), defaults: defaults)
        var rescheduled = original
        rescheduled.plannedDepartureAt = departure.addingTimeInterval(7200)
        rescheduled.plannedArrivalAt = departure.addingTimeInterval(10800)
        store.update(rescheduled)
        XCTAssertEqual(TripActivityService.eligibleTickets([rescheduled], defaults: defaults).map(\.id), [original.id])
    }

    @MainActor
    func testArrivalHandoffKeepsBEligibleWhenAWasDismissed() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let arrivalA = Ticket.scheduleDate(day: "2026-10-09", time: "09:00")!
        let first = scheduledTicket(departure: arrivalA.addingTimeInterval(-3600), arrival: arrivalA)
        let second = scheduledTicket(departure: arrivalA.addingTimeInterval(1200),
                                     arrival: arrivalA.addingTimeInterval(4800))
        let store = TripStore(defaults: defaults)
        store.add(first)
        store.add(second)
        TripActivityService.recordDismissal(attributes: activityAttributes(for: first), defaults: defaults)

        let eligible = TripActivityService.eligibleTickets(store.tickets, defaults: defaults)
        XCTAssertEqual(eligible.map(\.id), [second.id])
        XCTAssertEqual(TripActivityService.ticketForActivity(
            tickets: eligible, selectedTicketID: second.id, now: arrivalA)?.id, second.id)
        XCTAssertTrue(TripScheduleRules.isWithinAutomaticWindow(
            departure: second.plannedDepartureAt!, arrival: second.plannedArrivalAt!, now: arrivalA))
        XCTAssertTrue(TripActivityService.shouldStartLocally(
            requestedTicketID: nil, handoffTicketID: second.id,
            startAutomaticallyLocally: false, inAutomaticWindow: true, isForeground: true))
        XCTAssertFalse(TripActivityService.shouldStartLocally(
            requestedTicketID: nil, handoffTicketID: second.id,
            startAutomaticallyLocally: false, inAutomaticWindow: false, isForeground: true))
        XCTAssertFalse(TripActivityService.shouldStartLocally(
            requestedTicketID: nil, handoffTicketID: second.id,
            startAutomaticallyLocally: false, inAutomaticWindow: true, isForeground: false))
        XCTAssertFalse(TripActivityService.shouldStartLocally(
            requestedTicketID: second.id, handoffTicketID: nil,
            startAutomaticallyLocally: true, inAutomaticWindow: true, isForeground: false))
    }

    @MainActor
    func testNewOrRescheduledJourneyBecomesLocallyEligibleImmediately() {
        let now = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let departureOutsideWindow = now.addingTimeInterval(5 * 60 * 60)
        var edited = scheduledTicket(departure: departureOutsideWindow,
                                     arrival: departureOutsideWindow.addingTimeInterval(60 * 60))
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TripStore(defaults: defaults)
        store.add(edited)
        XCTAssertNil(TripActivityService.ticketForActivity(tickets: store.tickets,
                                                            selectedTicketID: nil, now: now))

        edited.plannedDepartureAt = now.addingTimeInterval(2 * 60 * 60 + 59 * 60)
        edited.plannedArrivalAt = edited.plannedDepartureAt?.addingTimeInterval(60 * 60)
        store.update(edited)
        XCTAssertEqual(TripActivityService.ticketForActivity(tickets: store.tickets,
                                                              selectedTicketID: nil, now: now)?.id, edited.id)

        let newlyAdded = scheduledTicket(departure: now.addingTimeInterval(2 * 60 * 60),
                                         arrival: now.addingTimeInterval(3 * 60 * 60))
        store.add(newlyAdded)
        XCTAssertNotNil(TripActivityService.ticketForActivity(tickets: [newlyAdded],
                                                               selectedTicketID: nil, now: now))
    }

    @MainActor
    func testBackgroundArrivalHandoffPublishesUpdatedPushScheduleSelection() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let arrival = Ticket.scheduleDate(day: "2026-10-09", time: "09:00")!
        let first = scheduledTicket(departure: arrival.addingTimeInterval(-60 * 60), arrival: arrival)
        let second = scheduledTicket(departure: arrival, arrival: arrival.addingTimeInterval(60 * 60))
        let store = TripStore(defaults: defaults)
        store.add(first)
        store.add(second)
        store.selectForWatch(id: first.id)

        var publishedSelection: UUID?
        var publishedTickets: [UUID] = []
        let success = await TripBackgroundRefreshService.refresh(
            now: arrival, defaults: defaults,
            updateActivity: { _, _, _, _ in },
            syncWatch: { _, _ in true },
            updatePushSchedule: { tickets, selectedID, enabled in
                XCTAssertTrue(enabled)
                publishedTickets = tickets.map(\.id)
                publishedSelection = selectedID
            })

        XCTAssertTrue(success)
        XCTAssertEqual(publishedSelection, second.id)
        XCTAssertEqual(Set(publishedTickets), Set([first.id, second.id]))
    }

    @MainActor
    func testDeletedOrRescheduledSnapshotCannotRetainOldScheduledTicket() throws {
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = departure.addingTimeInterval(60 * 60)
        let original = scheduledTicket(departure: departure, arrival: arrival)
        var edited = original
        edited.plannedDepartureAt = departure.addingTimeInterval(4 * 60 * 60)
        edited.plannedArrivalAt = arrival.addingTimeInterval(4 * 60 * 60)

        let originalScheduled = try XCTUnwrap(ActivityPushTokenService.ScheduledTicket(original, now: departure))
        let editedScheduled = try XCTUnwrap(ActivityPushTokenService.ScheduledTicket(edited, now: departure))
        XCTAssertNotEqual(originalScheduled.departureAt, editedScheduled.departureAt)

        let replacement = ActivityPushTokenService.ScheduleSnapshot(
            deviceID: UUID(), snapshotVersion: 201, enabled: true, pushToStartToken: "aabb", selectedTicketID: edited.id,
            tickets: [editedScheduled], activityTokens: [])
        XCTAssertFalse(replacement.tickets.contains { $0.departureAt == originalScheduled.departureAt })

        let deleted = ActivityPushTokenService.ScheduleSnapshot(
            deviceID: replacement.deviceID, snapshotVersion: 202, enabled: true, pushToStartToken: "aabb",
            selectedTicketID: nil, tickets: [], activityTokens: [])
        XCTAssertTrue(deleted.tickets.isEmpty)
    }

    @MainActor
    func testConcurrentLocalAndRemoteStartsKeepOneMatchingActivity() {
        let localActivityID = "local-request"
        let remoteActivityID = "remote-push-to-start"

        let duplicatesWhenRemoteArrivesFirst = TripActivityService.duplicateActivityIDs(
            [remoteActivityID, localActivityID])
        XCTAssertEqual(duplicatesWhenRemoteArrivesFirst, [localActivityID])

        let duplicatesWhenLocalArrivesFirst = TripActivityService.duplicateActivityIDs(
            [localActivityID, remoteActivityID])
        XCTAssertEqual(duplicatesWhenLocalArrivesFirst, [remoteActivityID])
        XCTAssertEqual(TripActivityService.duplicateActivityIDs(
            [localActivityID, remoteActivityID], keeping: remoteActivityID), [localActivityID])
    }

    @MainActor
    func testFarFutureTicketDoesNotBecomeArrivalHandoffSelection() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TripStore(defaults: defaults)
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = Ticket.scheduleDate(day: "2026-10-09", time: "09:00")!
        let farDeparture = departure.addingTimeInterval(10 * 60 * 60)
        let farArrival = farDeparture.addingTimeInterval(60 * 60)
        let first = scheduledTicket(departure: departure, arrival: arrival)
        let next = scheduledTicket(departure: farDeparture, arrival: farArrival)
        store.add(first)
        store.add(next)
        store.selectForWatch(id: first.id)

        XCTAssertTrue(store.refreshStatuses(at: arrival))
        XCTAssertNil(store.selectedTicketID)
    }

    @MainActor
    func testNextBoundaryIsDeterministicForIdempotentScheduling() {
        let departure = Ticket.scheduleDate(day: "2026-10-09", time: "08:00")!
        let arrival = departure.addingTimeInterval(2 * 60 * 60)
        let ticket = scheduledTicket(departure: departure, arrival: arrival)
        let now = departure.addingTimeInterval(-4 * 60 * 60)
        let first = TripBackgroundRefreshService.nextRequestDate(tickets: [ticket], after: now)
        let second = TripBackgroundRefreshService.nextRequestDate(tickets: [ticket], after: now)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, ticket.startAt)
    }

    @MainActor
    func testEditingTrainReplacesInFlightStationInfoRequest() async throws {
        let oldRequestStarted = expectation(description: "old train request started")
        let newRequestStarted = expectation(description: "edited train request started")
        let client = BlockingStationInfoClient(oldRequestStarted: oldRequestStarted,
                                               newRequestStarted: newRequestStarted)
        let store = TripStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                              stationInfoClient: client)
        let ticket = Ticket(id: UUID(), train: "G100", date: "2026-10-20", departTime: "08:00",
                            arriveTime: "10:00", from: "上海虹桥", to: "南京南", carriage: "01车",
                            seat: "01A", status: .upcoming, syncText: "")
        store.add(ticket)
        await fulfillment(of: [oldRequestStarted], timeout: 2)

        var edited = ticket
        edited.train = "G200"
        store.update(edited)
        await fulfillment(of: [newRequestStarted], timeout: 2)
        await store.refreshStationInfoAndWait(for: ticket.id, force: false)

        XCTAssertEqual(client.requestedTrains, ["G100", "G200"])
        XCTAssertEqual(store.tickets.first?.gate, "2A")
    }

    @MainActor
    func testTrainStationInfoRequestUsesExactBodyAndSharedHeaders() async throws {
        StationInfoURLProtocol.reset(statuses: [200], bodies: [Data(#"{"code":0,"data":{"departureDate":"2026-10-20","departureStation":"上海虹桥","trainNo":"G1826","matched":true,"waitingRoom":"5候车室","gate":"13A","checkingPort":"检票口13A","departTime":"08:00","waitingState":"正在候车","dayDiff":null}}"#.utf8)])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StationInfoURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration),
                                endpoint: URL(string: "https://api.example.com/api/apns/train-info"),
                                credentialsProvider: { APIRequestCredentials(token: "access", userLoginToken: "login") },
                                retryLimit: 1, retryDelay: { _ in })

        let response = try await client.getTrainStationInfo(
            departureDate: " 2026-10-20 ", departureStation: " 上海虹桥 ", trainNo: " g1826 ")
        XCTAssertTrue(response.data?.matched == true)
        let request = try XCTUnwrap(StationInfoURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "packageName"), Bundle.main.bundleIdentifier ?? "com.clenson.wristtrip")
        XCTAssertEqual(request.value(forHTTPHeaderField: "token"), "access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "userLoginToken"), "login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
        let constructedRequest = try APIClient.trainStationInfoRequest(
            departureDate: " 2026-10-20 ", departureStation: " 上海虹桥 ", trainNo: " g1826 ",
            endpoint: URL(string: "https://api.example.com/api/apns/train-info")!,
            credentials: APIRequestCredentials(token: "access", userLoginToken: "login"))
        let rawBody = try XCTUnwrap(constructedRequest.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: rawBody) as? [String: String])
        XCTAssertEqual(body, ["departureDate": "2026-10-20", "departureStation": "上海虹桥", "trainNo": "g1826"])
    }

    @MainActor
    func testTrainStationInfoUnmatchedDoesNotRetryOrMutateLocalValues() async throws {
        StationInfoURLProtocol.reset(statuses: [200], bodies: [Data(#"{"code":0,"data":{"matched":false}}"#.utf8)])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StationInfoURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration),
                                endpoint: URL(string: "https://api.example.com/api/apns/train-info"),
                                credentialsProvider: { APIRequestCredentials(token: "access", userLoginToken: nil) },
                                retryLimit: 3, retryDelay: { _ in })
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = TripStore(defaults: defaults, stationInfoClient: client)
        let ticket = Ticket(id: UUID(), train: "G1826", date: "2026-10-20", departTime: "08:00", arriveTime: "10:00",
                            from: "上海虹桥", to: "南京南", carriage: "01车", seat: "01A",
                            waitingRoom: "原候车室", gate: "原检票口", status: .upcoming, syncText: "")
        store.add(ticket)
        await store.refreshStationInfoAndWait(for: ticket.id, force: true)
        XCTAssertEqual(store.tickets.first?.waitingRoom, "原候车室")
        XCTAssertEqual(store.tickets.first?.gate, "原检票口")
        XCTAssertEqual(StationInfoURLProtocol.requestCount, 1)
    }

    @MainActor
    func testTrainStationInfoParameterErrorIsNotRetriedAndServerErrorsBackoff() async throws {
        StationInfoURLProtocol.reset(statuses: [200], bodies: [Data(#"{"code":2,"err":"missing"}"#.utf8)])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StationInfoURLProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration),
                                endpoint: URL(string: "https://api.example.com/api/apns/train-info"),
                                credentialsProvider: { APIRequestCredentials(token: "access", userLoginToken: nil) },
                                retryLimit: 3, retryDelay: { _ in })
        do {
            _ = try await client.getTrainStationInfo(departureDate: "2026-10-20", departureStation: "上海虹桥", trainNo: "G1826")
            XCTFail("expected code 2")
        } catch let error as TrainStationInfoAPIError {
            XCTAssertEqual(error, .business(code: 2, message: "missing"))
        }
        XCTAssertEqual(StationInfoURLProtocol.requestCount, 1)

        StationInfoURLProtocol.reset(statuses: [502, 500, 200], bodies: [
            Data(#"{"code":502}"#.utf8), Data(#"{"code":1}"#.utf8),
            Data(#"{"code":0,"data":{"matched":false}}"#.utf8)
        ])
        _ = try await client.getTrainStationInfo(departureDate: "2026-10-20", departureStation: "上海虹桥", trainNo: "G1826")
        XCTAssertEqual(StationInfoURLProtocol.requestCount, 3)
    }

    private func scheduledTicket(departure: Date, arrival: Date) -> Ticket {
        Ticket(id: UUID(), train: "G1", date: "2026-10-09", departTime: "08:00", arriveTime: "09:00",
               from: "北京南", to: "天津南", carriage: "01车", seat: "01A", waitingRoom: "待公布",
               gate: "待公布", status: .upcoming, syncText: "", plannedDepartureAt: departure, plannedArrivalAt: arrival)
    }

    private func activityAttributes(for ticket: Ticket) -> TripActivityAttributes {
        TripActivityAttributes(ticketID: ticket.id, train: ticket.train, origin: ticket.from,
                               destination: ticket.to, departureAt: ticket.plannedDepartureAt!,
                               arrivalAt: ticket.plannedArrivalAt!, timezoneIdentifier: ticket.originalTimezoneIdentifier,
                               carriage: ticket.carriage, seat: ticket.seat, seatClass: ticket.seatClass,
                               fare: ticket.fare)
    }

    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> OCRLine {
        OCRLine(text: text, x: x, y: y)
    }
}

@MainActor
private final class BlockingStationInfoClient: TrainStationInfoProviding {
    let oldRequestStarted: XCTestExpectation
    let newRequestStarted: XCTestExpectation
    var requestedTrains: [String] = []

    init(oldRequestStarted: XCTestExpectation, newRequestStarted: XCTestExpectation) {
        self.oldRequestStarted = oldRequestStarted
        self.newRequestStarted = newRequestStarted
    }

    func getTrainStationInfo(departureDate: String, departureStation: String,
                             trainNo: String) async throws -> TrainStationInfoResponse {
        requestedTrains.append(trainNo)
        if trainNo == "G100" {
            oldRequestStarted.fulfill()
            try await Task.sleep(for: .seconds(30))
        } else {
            newRequestStarted.fulfill()
        }
        return TrainStationInfoResponse(code: 0,
            data: TrainStationInfoData(departureDate: departureDate, departureStation: departureStation,
                                       trainNo: trainNo, matched: true, gate: "2A"), err: nil)
    }
}

private final class StationInfoURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var statuses: [Int] = []
    nonisolated(unsafe) private static var bodies: [Data] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset(statuses: [Int], bodies: [Data]) {
        self.statuses = statuses
        self.bodies = bodies
        requestCount = 0
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequest = request
        let index = min(Self.requestCount - 1, Self.statuses.count - 1)
        let status = Self.statuses[max(0, index)]
        let body = Self.bodies[min(max(0, index), Self.bodies.count - 1)]
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
