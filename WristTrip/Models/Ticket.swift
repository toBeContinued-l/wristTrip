import Foundation
import SwiftUI

enum TicketStatus: String, Codable, CaseIterable {
    case upcoming = "待出发"
    case boarding = "临近发车"
    case onboard = "已发车"
    case arrived = "已到站"

    static func forSchedule(departure: Date?, arrival: Date?, now: Date = Date(), boardingWindow: TimeInterval = 30 * 60) -> TicketStatus {
        guard let departure else { return .upcoming }
        if now < departure.addingTimeInterval(-boardingWindow) { return .upcoming }
        if now < departure { return .boarding }
        guard let arrival else { return .onboard }
        return now < arrival ? .onboard : .arrived
    }
}

enum TicketFieldSource: String, Codable {
    case screenshot = "截图识别"
    case manual = "手动修改"
    case officialQuery = "12306官网查询"
}

struct Ticket: Identifiable, Codable {
    let id: UUID
    var train: String
    /// Display date retained for the existing SwiftUI prototype.
    var date: String
    /// Display times retained for the existing SwiftUI prototype.
    var departTime: String
    var arriveTime: String
    var from: String
    var to: String
    var carriage: String
    var seat: String
    var seatClass: String
    var fare: String
    var waitingRoom: String
    /// Original gate text as shown on the imported ticket.
    var gate: String
    /// Optional 12306 boarding-station telecode required by the official query page.
    var fromStationTelecode: String?
    var gateQueriedAt: Date?
    var gateQueryRawResponse: String?
    var status: TicketStatus
    var syncText: String
    var syncTone: Color = .green
    var sourceText: String = "来自导入截图"

    /// Absolute planned times. Optional values permit incomplete imports to be saved as drafts.
    var plannedDepartureAt: Date?
    var plannedArrivalAt: Date?
    var originalTimezoneIdentifier: String
    var durationMinutes: Int?
    var normalizedGates: [String]
    var importedAt: Date
    var updatedAt: Date
    var fieldSources: [String: TicketFieldSource]

    private enum CodingKeys: String, CodingKey {
        case id, train, date, departTime, arriveTime, from, to, carriage, seat, seatClass, fare, waitingRoom, gate
        case fromStationTelecode, gateQueriedAt, gateQueryRawResponse
        case status, syncText, sourceText, plannedDepartureAt, plannedArrivalAt
        case originalTimezoneIdentifier, durationMinutes, normalizedGates, importedAt, updatedAt, fieldSources
    }

    init(id: UUID, train: String, date: String, departTime: String, arriveTime: String, from: String, to: String,
         carriage: String, seat: String, waitingRoom: String, gate: String, status: TicketStatus, syncText: String,
         syncTone: Color = .green, sourceText: String = "来自导入截图", plannedDepartureAt: Date? = nil,
         plannedArrivalAt: Date? = nil, originalTimezoneIdentifier: String = "Asia/Shanghai", durationMinutes: Int? = nil,
         normalizedGates: [String]? = nil, importedAt: Date = Date(), updatedAt: Date = Date(),
         fieldSources: [String: TicketFieldSource] = [:], fromStationTelecode: String? = nil,
         gateQueriedAt: Date? = nil, gateQueryRawResponse: String? = nil, seatClass: String = "", fare: String = "") {
        self.id = id
        self.train = train
        self.date = date
        self.departTime = departTime
        self.arriveTime = arriveTime
        self.from = from
        self.to = to
        self.carriage = carriage
        self.seat = seat
        self.seatClass = seatClass
        self.fare = fare
        self.waitingRoom = waitingRoom
        self.gate = gate
        self.fromStationTelecode = fromStationTelecode
        self.gateQueriedAt = gateQueriedAt
        self.gateQueryRawResponse = gateQueryRawResponse
        self.status = status
        self.syncText = syncText
        self.syncTone = syncTone
        self.sourceText = sourceText
        self.plannedDepartureAt = plannedDepartureAt
        self.plannedArrivalAt = plannedArrivalAt
        self.originalTimezoneIdentifier = originalTimezoneIdentifier
        self.durationMinutes = durationMinutes
        self.normalizedGates = normalizedGates ?? Self.normalizeGates(gate)
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.fieldSources = fieldSources
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        train = try values.decode(String.self, forKey: .train)
        date = try values.decode(String.self, forKey: .date)
        departTime = try values.decode(String.self, forKey: .departTime)
        arriveTime = try values.decode(String.self, forKey: .arriveTime)
        from = try values.decode(String.self, forKey: .from)
        to = try values.decode(String.self, forKey: .to)
        carriage = try values.decode(String.self, forKey: .carriage)
        seat = try values.decode(String.self, forKey: .seat)
        seatClass = try values.decodeIfPresent(String.self, forKey: .seatClass) ?? ""
        fare = try values.decodeIfPresent(String.self, forKey: .fare) ?? ""
        waitingRoom = try values.decode(String.self, forKey: .waitingRoom)
        gate = try values.decode(String.self, forKey: .gate)
        fromStationTelecode = try values.decodeIfPresent(String.self, forKey: .fromStationTelecode)
        gateQueriedAt = try values.decodeIfPresent(Date.self, forKey: .gateQueriedAt)
        gateQueryRawResponse = try values.decodeIfPresent(String.self, forKey: .gateQueryRawResponse)
        status = try values.decodeIfPresent(TicketStatus.self, forKey: .status) ?? .upcoming
        syncText = try values.decode(String.self, forKey: .syncText)
        sourceText = try values.decodeIfPresent(String.self, forKey: .sourceText) ?? "来自导入截图"
        plannedDepartureAt = try values.decodeIfPresent(Date.self, forKey: .plannedDepartureAt)
        plannedArrivalAt = try values.decodeIfPresent(Date.self, forKey: .plannedArrivalAt)
        originalTimezoneIdentifier = try values.decodeIfPresent(String.self, forKey: .originalTimezoneIdentifier) ?? "Asia/Shanghai"
        durationMinutes = try values.decodeIfPresent(Int.self, forKey: .durationMinutes)
        normalizedGates = try values.decodeIfPresent([String].self, forKey: .normalizedGates) ?? Self.normalizeGates(gate)
        importedAt = try values.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? importedAt
        fieldSources = try values.decodeIfPresent([String: TicketFieldSource].self, forKey: .fieldSources) ?? [:]
        syncTone = .green
    }

    /// Calculates app state from plan times; it does not represent live railway information.
    func status(at now: Date = Date()) -> TicketStatus {
        TicketStatus.forSchedule(departure: plannedDepartureAt, arrival: plannedArrivalAt, now: now)
    }

    /// Convenience name for views that need the state at the current instant.
    var calculatedStatus: TicketStatus { status(at: Date()) }

    /// Common aliases make the absolute fields explicit at call sites while preserving the original field names.
    var departureDate: Date? {
        get { plannedDepartureAt }
        set { plannedDepartureAt = newValue }
    }

    var arrivalDate: Date? {
        get { plannedArrivalAt }
        set { plannedArrivalAt = newValue }
    }

    mutating func refreshStatus(at now: Date = Date()) {
        status = status(at: now)
    }

    var startAt: Date? { plannedDepartureAt?.addingTimeInterval(-3 * 60 * 60) }
    var endAt: Date? { plannedArrivalAt }

    var isDraft: Bool {
        train.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || plannedDepartureAt == nil || from.isEmpty || to.isEmpty
    }

    var displayTimezone: TimeZone {
        TimeZone(identifier: originalTimezoneIdentifier) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    static func scheduleDate(day: String, time: String, timezone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!) -> Date? {
        guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              time.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { return nil }
        let values = (day + "-" + time.replacingOccurrences(of: ":", with: "-"))
            .split(separator: "-").compactMap { Int($0) }
        guard values.count == 5 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let components = DateComponents(year: values[0], month: values[1], day: values[2], hour: values[3], minute: values[4])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date) == components else { return nil }
        return date
    }

    /// Placeholder values such as "待公布" are not usable gate data.
    var hasUsableGate: Bool {
        !Self.normalizeGates(gate).isEmpty
    }

    static func normalizeGates(_ value: String) -> [String] {
        value.replacingOccurrences(of: "检票口", with: "")
            .replacingOccurrences(of: "以现场公告为准", with: "")
            .replacingOccurrences(of: "如有变更", with: "")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":："))) }
            .filter { !$0.isEmpty && $0 != "待公布" && $0 != "待补充" }
    }
}

extension Ticket {
    static let next = Ticket(id: UUID(), train: "G1088", date: "10月08日 周四", departTime: "08:42", arriveTime: "12:16",
                             from: "上海虹桥", to: "南京南", carriage: "06车", seat: "12A", waitingRoom: "待公布",
                             gate: "13A、13B", status: .upcoming, syncText: "手表同步待配置", syncTone: .secondary,
                             plannedDepartureAt: sampleDate(day: 1, hour: 8, minute: 42),
                             plannedArrivalAt: sampleDate(day: 1, hour: 12, minute: 16))

    static let history = Ticket(id: UUID(), train: "D2281", date: "10月05日 周一", departTime: "09:05", arriveTime: "13:22",
                                from: "上海虹桥", to: "杭州东", carriage: "04车", seat: "08C", waitingRoom: "5候车室",
                                gate: "B12", status: .arrived, syncText: "已结束", syncTone: .secondary,
                                plannedDepartureAt: sampleDate(day: -2, hour: 9, minute: 5),
                                plannedArrivalAt: sampleDate(day: -2, hour: 13, minute: 22))

    private static func sampleDate(day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let date = calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day, hour: hour, minute: minute))!
        return date.addingTimeInterval(TimeInterval(day) * 24 * 60 * 60)
    }
}
