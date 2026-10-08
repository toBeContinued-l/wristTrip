import Foundation

struct TicketGateLookupResult {
    let rawText: String
    let gates: [String]
    let queriedAt: Date
}

enum TicketGateLookupError: LocalizedError {
    case missingTelecode
    case invalidDate
    case invalidResponse
    case noGate

    var errorDescription: String? {
        switch self {
        case .missingTelecode: return "缺少乘车站电报码，无法查询检票口"
        case .invalidDate: return "出行日期无效，无法查询检票口"
        case .invalidResponse: return "12306 检票口查询返回格式无法识别"
        case .noGate: return "12306 当前没有返回检票口，已保留原值"
        }
    }
}

/// Opt-in client for the 12306 ticket-check page's internal endpoint.
/// It intentionally sends no cookies, login credentials, screenshots, or passenger data.
struct TicketGateLookupService {
    private let endpoint = URL(string: "https://www.12306.cn/index/otn/index12306/queryTicketCheck")!
    private static let maxResponseBytes = 1_048_576
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // This endpoint is queried without an account session or caller-provided cookies.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func query(ticket: Ticket, now: Date = Date()) async throws -> TicketGateLookupResult {
        guard let telecode = ticket.fromStationTelecode?.trimmingCharacters(in: .whitespacesAndNewlines), !telecode.isEmpty else {
            throw TicketGateLookupError.missingTelecode
        }
        guard let departure = ticket.plannedDepartureAt else { throw TicketGateLookupError.invalidDate }
        let train = ticket.train.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !train.isEmpty else { throw TicketGateLookupError.invalidResponse }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ticket.displayTimezone
        formatter.dateFormat = "yyyy-MM-dd"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.12306.cn", forHTTPHeaderField: "Origin")
        request.setValue("https://www.12306.cn/index/view/infos/ticket_check.html", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("WristTrip/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = formData([
            ("trainDate", formatter.string(from: departure)),
            ("station_train_code", train),
            ("from_station_telecode", telecode.uppercased())
        ]).data(using: .utf8)

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TicketGateLookupError.invalidResponse
        }
        // Keep an unexpected proxy/error page from being persisted in a Ticket.
        guard data.count <= Self.maxResponseBytes else { throw TicketGateLookupError.invalidResponse }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw TicketGateLookupError.invalidResponse
        }
        let rawText = String(data: data, encoding: .utf8) ?? ""
        let gates = Self.extractGates(from: object)
        guard !gates.isEmpty else { throw TicketGateLookupError.noGate }
        return TicketGateLookupResult(rawText: rawText, gates: gates, queriedAt: now)
    }

    static func extractGates(from object: Any) -> [String] {
        var candidates: [String] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, nested) in dictionary {
                    let normalizedKey = key.replacingOccurrences(of: "_", with: "").lowercased()
                    if ["trainplatform", "platform", "ticketcheck", "platformname", "platformno", "gate", "gatename", "checkgate", "检票口"].contains(normalizedKey) {
                        collect(nested)
                    }
                    walk(nested)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        func collect(_ value: Any) {
            if let string = value as? String { candidates.append(string) }
            else if let array = value as? [Any] { array.forEach { collect($0) } }
            else if let dictionary = value as? [String: Any] {
                for key in ["name", "platform", "trainPlatform", "platformName", "platformNo", "ticketCheck", "gate", "gateName", "checkGate", "检票口"] where dictionary[key] != nil {
                    collect(dictionary[key]!)
                }
            }
        }
        walk(object)
        var seen = Set<String>()
        return normalizeGates(candidates.joined(separator: "、")).filter { seen.insert($0).inserted }
    }

    private static func normalizeGates(_ text: String) -> [String] {
        text.replacingOccurrences(of: "检票口", with: "")
            .replacingOccurrences(of: "以现场公告为准", with: "")
            .replacingOccurrences(of: "如有变更", with: "")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":："))) }
            .filter { value in
                guard !value.isEmpty, value.count <= 12 else { return false }
                return value.range(of: #"^[0-9A-Za-z一二三四五六七八九十]+(?:[-至/][0-9A-Za-z一二三四五六七八九十]+)?$"#, options: .regularExpression) != nil
            }
    }

    private func formData(_ values: [(String, String)]) -> String {
        values.map { "\(Self.escape($0.0))=\(Self.escape($0.1))" }.joined(separator: "&")
    }

    private static func escape(_ value: String) -> String {
        // Encode as application/x-www-form-urlencoded. URLQueryAllowed leaves
        // characters such as '?' and '/' unescaped, which is not valid here.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }
}
