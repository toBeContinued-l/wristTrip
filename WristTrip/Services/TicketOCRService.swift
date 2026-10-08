import Foundation
import UIKit
@preconcurrency import Vision

struct OCRSeat: Hashable {
    let carriage: String
    let seat: String
    let seatClass: String

    init(carriage: String, seat: String, seatClass: String = "") {
        self.carriage = carriage
        self.seat = seat
        self.seatClass = seatClass
    }
}

struct OCRTicketFields {
    var train: String?
    var travelDate: String?
    var departureTime: String?
    var arrivalDate: String?
    var arrivalTime: String?
    var from: String?
    var to: String?
    var waitingRoom: String?
    var gate: String?
    var fare: String?
    var durationMinutes: Int?
    var seats: [OCRSeat] = []

    init(train: String? = nil, travelDate: String? = nil, departureTime: String? = nil,
         arrivalDate: String? = nil, arrivalTime: String? = nil, from: String? = nil,
         to: String? = nil, waitingRoom: String? = nil, gate: String? = nil, fare: String? = nil,
         durationMinutes: Int? = nil, seats: [OCRSeat] = []) {
        self.train = train
        self.travelDate = travelDate
        self.departureTime = departureTime
        self.arrivalDate = arrivalDate
        self.arrivalTime = arrivalTime
        self.from = from
        self.to = to
        self.waitingRoom = waitingRoom
        self.gate = gate
        self.fare = fare
        self.durationMinutes = durationMinutes
        self.seats = seats
    }

    init(train: String?, departureTime: String?, arrivalTime: String?, from: String?,
         to: String?, gate: String?, durationMinutes: Int?) {
        self.init(train: train, travelDate: nil, departureTime: departureTime,
                  arrivalDate: nil, arrivalTime: arrivalTime, from: from, to: to,
                  gate: gate, durationMinutes: durationMinutes, seats: [])
    }
}

struct OCRLine {
    let text: String
    let x: CGFloat
    let y: CGFloat
}

enum TicketOCRServiceError: LocalizedError {
    case noText
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .noText: return "图片中没有识别到文字，可手动填写"
        case .invalidImage: return "无法读取所选图片，请重新选择"
        }
    }
}

struct TicketOCRService {
    /// Backwards-compatible raw OCR entry point. The review flow uses recognizeLines(in:)
    /// so parsing can use the text's image coordinates.
    func recognizeText(in image: UIImage) async throws -> String {
        try await recognizeLines(in: image).map(\.text).joined(separator: "\n")
    }

    func recognizeLines(in image: UIImage) async throws -> [OCRLine] {
        guard let cgImage = image.cgImage else { throw TicketOCRServiceError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { observation -> OCRLine? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return OCRLine(text: candidate.string, x: observation.boundingBox.midX,
                                       y: observation.boundingBox.midY)
                    }
                    .sorted { abs($0.y - $1.y) > 0.012 ? $0.y > $1.y : $0.x < $1.x }
                guard !lines.isEmpty else {
                    continuation.resume(throwing: TicketOCRServiceError.noText)
                    return
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func parse(_ lines: [OCRLine]) -> OCRTicketFields {
        var fields = OCRTicketFields()
        guard let trainLine = lines.first(where: { match($0.text, #"\b[DGCKTZYS]\s?\d{1,4}\b"#) != nil }) else {
            return fields
        }
        let boundary = lines.first(where: { $0.y < trainLine.y &&
            containsAny($0.text, ["乘车人", "乘客信息", "订单信息", "订单号", "酒店", "推荐服务", "温馨提示"])
        })?.y ?? 0
        let ticketLines = lines.filter { $0.y >= boundary && abs($0.y - trainLine.y) < 0.32 }
        fields.train = match(trainLine.text, #"\b[DGCKTZYS]\s?\d{1,4}\b"#)?
            .replacingOccurrences(of: " ", with: "").uppercased()

        // The date label can sit just outside the train card's vertical bounds.
        // Keep the same order/advertising exclusions, but search the full OCR
        // result so a boundary pixel does not drop the travel date.
        let datedLines = lines.filter { !containsAny($0.text, ["下单", "支付", "预订", "酒店", "订单"]) }
        fields.travelDate = datedLines.first(where: { containsAny($0.text, ["出发", "乘车", "发车"]) })
            .flatMap { fullDate(in: $0.text) }
        if fields.travelDate == nil {
            let candidates = datedLines.compactMap { fullDate(in: $0.text) }
            if Set(candidates).count == 1 { fields.travelDate = candidates.first }
        }
        fields.arrivalDate = datedLines.first(where: { containsAny($0.text, ["到达日期", "到站日期"]) })
            .flatMap { fullDate(in: $0.text) }

        let routeLine = ticketLines.first { $0.text.contains("→") || $0.text.contains("->") || $0.text.contains("—") }
        if let routeLine {
            let separator = routeLine.text.contains("→") ? "→" : (routeLine.text.contains("->") ? "->" : "—")
            let parts = routeLine.text.components(separatedBy: separator)
            if parts.count == 2 {
                fields.from = station(parts[0])
                fields.to = station(parts[1])
            }
        }
        if fields.from == nil || fields.to == nil {
            fields.from = fields.from ?? ticketLines.first(where: { $0.text.contains("出发站") })
                .flatMap { station($0.text.replacingOccurrences(of: "出发站", with: "")) }
            fields.to = fields.to ?? ticketLines.first(where: { $0.text.contains("到达站") })
                .flatMap { station($0.text.replacingOccurrences(of: "到达站", with: "")) }
        }
        let timeAnchor = routeLine?.y ?? trainLine.y
        let timeLines = ticketLines.filter {
            abs($0.y - timeAnchor) < 0.13 &&
            !containsAny($0.text, ["下单", "支付", "预订", "酒店", "订单", "广告", "历时"])
        }
        let timeCandidates = timeLines.flatMap { line in
            matches(line.text, #"(?<!\d)(?:[01]?\d|2[0-3])[:：][0-5]\d(?!\d)"#)
                .map { (time: $0.replacingOccurrences(of: "：", with: ":"), x: line.x, y: line.y) }
        }
        if timeCandidates.count == 2 {
            let ordered = timeCandidates.sorted { abs($0.y - $1.y) < 0.025 ? $0.x < $1.x : $0.y > $1.y }
            fields.departureTime = ordered[0].time
            fields.arrivalTime = ordered[1].time
        }

        // 12306's compact order card puts each station close to its
        // corresponding time. There is no route arrow between the station
        // labels, so use the time row as the spatial anchor and pair the
        // left/right labels.
        if fields.from == nil || fields.to == nil {
            if let pair = stationsBelowTimes(in: ticketLines, times: timeCandidates) {
                fields.from = fields.from ?? pair.0
                fields.to = fields.to ?? pair.1
            } else {
                let stationAnchor = timeCandidates.map(\.y).first ?? routeLine?.y ?? trainLine.y
                if let pair = spatialStations(in: ticketLines, near: stationAnchor) {
                    fields.from = fields.from ?? pair.0
                    fields.to = fields.to ?? pair.1
                }
            }
        }

        if let durationLine = ticketLines.first(where: { containsAny($0.text, ["历时", "运行时间"]) }) {
            let hours = match(durationLine.text, #"\d+\s*(?:小时|时)"#)
                .flatMap { Int($0.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) } ?? 0
            let minutes = match(durationLine.text, #"\d+\s*分"#)
                .flatMap { Int($0.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) } ?? 0
            if hours + minutes > 0 { fields.durationMinutes = hours * 60 + minutes }
        }
        if fields.arrivalDate == nil, let day = fields.travelDate,
           let departureTime = fields.departureTime, let arrivalTime = fields.arrivalTime,
           let duration = fields.durationMinutes, let departure = scheduled(day, departureTime) {
            let arrival = departure.addingTimeInterval(TimeInterval(duration * 60))
            if clockString(arrival) == arrivalTime { fields.arrivalDate = dateString(arrival) }
        }

        fields.waitingRoom = ticketLines.first(where: { $0.text.contains("候车室") })
            .flatMap { labeledValue($0.text, label: "候车室") }
        fields.gate = ticketLines.first(where: { $0.text.contains("检票口") })
            .flatMap { labeledValue($0.text, label: "检票口") }

        fields.fare = lines.compactMap { fare(in: $0.text) }.first ?? splitFare(in: lines)

        // The passenger heading is often absent from a cropped 12306 screenshot.
        // Identify visible seat rows by their carriage and seat tokens instead.
        let seatLines = lines.filter {
            $0.y < trainLine.y && trainLine.y - $0.y < 0.55
        }
        fields.seats = Array(Set(seatLines.compactMap { line -> OCRSeat? in
                guard let carriage = match(line.text, #"\d{1,2}\s*车(?:厢)?"#),
                      let seat = match(line.text, #"\d{1,3}(?:[A-F]|\s*号)"#) else { return nil }
                let seatClass = match(line.text, #"(?:商务座|特等座|一等座|二等座|软卧|硬卧|软座|硬座|无座)"#) ?? ""
                return OCRSeat(carriage: carriage, seat: seat.replacingOccurrences(of: "号", with: ""), seatClass: seatClass)
            })).sorted { $0.carriage + $0.seat < $1.carriage + $1.seat }
        return fields
    }

    /// Compatibility adapter for callers that already have plain OCR text.
    /// Without coordinates, each line is assigned a stable top-to-bottom position;
    /// the same conservative parser still rejects ambiguous field candidates.
    func parse(_ text: String) -> OCRTicketFields {
        let values = text.split(whereSeparator: \.isNewline).map(String.init)
        let count = max(values.count, 1)
        let lines = values.enumerated().map { index, value in
            OCRLine(text: value, x: 0.5, y: 1 - CGFloat(index) / CGFloat(count))
        }
        return parse(lines)
    }

    private func labeledValue(_ text: String, label: String) -> String? {
        guard let range = text.range(of: label) else { return nil }
        let value = text[range.upperBound...].replacingOccurrences(of: #"^(?:\s|[:：])+"#, with: "", options: .regularExpression)
            .components(separatedBy: "如有变更").first?
            .components(separatedBy: "以现场").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty, !containsAny(value, ["待公布", "暂无"]) else { return nil }
        return value
    }

    private func fare(in text: String) -> String? {
        if let value = match(text, #"[¥￥]\s*\d+(?:[.,]\d{1,2})?"#) {
            return value.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        }
        if let value = match(text, #"\d+(?:[.,]\d{1,2})?\s*元"#) {
            return value.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        }
        return nil
    }

    private func splitFare(in lines: [OCRLine]) -> String? {
        for currency in lines where currency.text.trimmingCharacters(in: .whitespacesAndNewlines) == "¥"
            || currency.text.trimmingCharacters(in: .whitespacesAndNewlines) == "￥" {
            let amount = lines.first { line in
                abs(line.y - currency.y) < 0.035 && abs(line.x - currency.x) < 0.16
                    && line.text.range(of: #"^\s*\d+(?:[.,]\d{1,2})?\s*$"#, options: .regularExpression) != nil
            }
            if let amount { return currency.text.trimmingCharacters(in: .whitespacesAndNewlines) + amount.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    private func station(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?:出发站|到达站|[:：\s])+|(?:[:：\s>›»＞])+?$"#, with: "", options: .regularExpression)
        guard !value.isEmpty, value.count <= 12,
              !containsAny(value, ["时间", "日期", "酒店", "订单", "历时", "检票",
                                   "经停", "车次", "乘车", "候车", "票价", "站台",
                                   "发车", "到站", "出发", "到达"]) else { return nil }
        return value
    }

    private func spatialStations(in lines: [OCRLine], near anchorY: CGFloat) -> (String, String)? {
        let candidates = lines.flatMap { line -> [(String, CGFloat, CGFloat)] in
            guard abs(line.y - anchorY) <= 0.30 else { return [] }
            return stationNames(in: line.text).map { ($0, line.x, line.y) }
        }
        return bestStationPair(candidates)
    }

    private func stationsBelowTimes(
        in lines: [OCRLine],
        times: [(time: String, x: CGFloat, y: CGFloat)]
    ) -> (String, String)? {
        guard times.count == 2 else { return nil }
        let orderedTimes = times.sorted { $0.x < $1.x }
        let stationCandidates = orderedTimes.map { time in
            lines.compactMap { line -> (name: String, y: CGFloat)? in
                // Vision's normalized Y axis grows upward, so the station
                // shown below each time has a smaller Y value. Ignore labels
                // above the time and choose only the nearby station row.
                guard line.y < time.y,
                      time.y - line.y <= 0.24,
                      abs(line.x - time.x) <= 0.20,
                      let name = stationCandidate(line.text) else { return nil }
                return (name, line.y)
            }
        }
        let pairs = stationCandidates[0].flatMap { left in
            stationCandidates[1].compactMap { right -> (String, String)? in
                guard left.name != right.name, abs(left.y - right.y) <= 0.055 else { return nil }
                return (left.name, right.name)
            }
        }
        guard pairs.count == 1 else { return nil }
        return pairs[0]
    }

    private func stationCandidate(_ raw: String) -> String? {
        let names = stationNames(in: raw)
        guard names.count == 1 else { return nil }
        return station(names[0])
    }

    private func stationNames(in raw: String) -> [String] {
        let compact = raw.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return matches(compact, #"[\p{Han}]{2,8}"#).compactMap(station)
    }

    private func bestStationPair(_ candidates: [(String, CGFloat, CGFloat)]) -> (String, String)? {
        let pairs = candidates.flatMap { left in
            candidates.compactMap { right -> (String, String, CGFloat)? in
                guard left.1 < 0.48, right.1 > 0.52,
                      left.0 != right.0,
                      abs(left.2 - right.2) <= 0.12 else { return nil }
                return (left.0, right.0, abs(left.2 - right.2) + abs(left.1 - right.1) * 0.05)
            }
        }.sorted { $0.2 < $1.2 }
        guard let best = pairs.first,
              pairs.dropFirst().first.map({ abs($0.2 - best.2) > 0.01 }) ?? true else { return nil }
        return (best.0, best.1)
    }

    private func fullDate(in text: String) -> String? {
        guard let value = match(text, #"\d{4}[年/.-]\d{1,2}[月/.-]\d{1,2}日?"#) else { return nil }
        let numbers = matches(value, #"\d+"#).compactMap(Int.init)
        guard numbers.count == 3 else { return nil }
        let formatted = String(format: "%04d-%02d-%02d", numbers[0], numbers[1], numbers[2])
        return scheduled(formatted, "00:00") == nil ? nil : formatted
    }

    private func scheduled(_ day: String, _ clock: String) -> Date? {
        let numbers = matches(day + " " + clock, #"\d+"#).compactMap(Int.init)
        guard numbers.count == 5 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let components = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2],
                                        hour: numbers[3], minute: numbers[4])
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return roundTrip == components ? date : nil
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func clockString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool { terms.contains { text.contains($0) } }
    private func match(_ text: String, _ pattern: String) -> String? { matches(text, pattern).first }

    private func matches(_ text: String, _ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
