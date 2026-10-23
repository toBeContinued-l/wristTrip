import Foundation
import OSLog

struct TrainStationInfoResponse: Codable, Equatable {
    let code: Int
    let data: TrainStationInfoData?
    let err: String?
}

struct TrainStationInfoData: Codable, Equatable {
    let departureDate: String
    let departureStation: String
    let trainNo: String
    let matched: Bool
    let waitingRoom: String
    let gate: String
    let checkingPort: String
    let departTime: String
    let waitingState: String
    let dayDiff: Int?

    init(departureDate: String, departureStation: String, trainNo: String,
         matched: Bool, waitingRoom: String = "", gate: String = "",
         checkingPort: String = "", departTime: String = "",
         waitingState: String = "", dayDiff: Int? = nil) {
        self.departureDate = departureDate
        self.departureStation = departureStation
        self.trainNo = trainNo
        self.matched = matched
        self.waitingRoom = waitingRoom
        self.gate = gate
        self.checkingPort = checkingPort
        self.departTime = departTime
        self.waitingState = waitingState
        self.dayDiff = dayDiff
    }

    private enum CodingKeys: String, CodingKey {
        case departureDate, departureStation, trainNo, matched, waitingRoom, gate,
             checkingPort, departTime, waitingState, dayDiff
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        departureDate = try values.decodeIfPresent(String.self, forKey: .departureDate) ?? ""
        departureStation = try values.decodeIfPresent(String.self, forKey: .departureStation) ?? ""
        trainNo = try values.decodeIfPresent(String.self, forKey: .trainNo) ?? ""
        matched = try values.decodeIfPresent(Bool.self, forKey: .matched) ?? false
        waitingRoom = try values.decodeIfPresent(String.self, forKey: .waitingRoom) ?? ""
        gate = try values.decodeIfPresent(String.self, forKey: .gate) ?? ""
        checkingPort = try values.decodeIfPresent(String.self, forKey: .checkingPort) ?? ""
        departTime = try values.decodeIfPresent(String.self, forKey: .departTime) ?? ""
        waitingState = try values.decodeIfPresent(String.self, forKey: .waitingState) ?? ""
        dayDiff = try values.decodeIfPresent(Int.self, forKey: .dayDiff)
    }
}

struct APIRequestCredentials: Equatable {
    let token: String
    let userLoginToken: String?
}

enum TrainStationInfoAPIError: Error, Equatable {
    case invalidParameters
    case invalidResponse
    case httpStatus(Int, code: Int?)
    case business(code: Int, message: String?)

    var isRetryable: Bool {
        switch self {
        case .httpStatus(500, _), .httpStatus(502, _): return true
        default: return false
        }
    }
}

protocol TrainStationInfoProviding: AnyObject {
    func getTrainStationInfo(departureDate: String, departureStation: String,
                             trainNo: String) async throws -> TrainStationInfoResponse
}

/// The app's API entry point. Authentication and common headers are supplied
/// by ActivityPushTokenService, so feature views never handle credentials.
@MainActor
final class APIClient: TrainStationInfoProviding {
    static let shared = APIClient()

    private let session: URLSession
    private let credentialsProvider: () async -> APIRequestCredentials?
    private let endpoint: URL?
    private let retryLimit: Int
    private let retryDelay: (Int) async -> Void
    private let logger = Logger(subsystem: "com.clenson.WristTrip", category: "TrainStationInfo")

    init(session: URLSession = .shared,
         endpoint: URL? = nil,
         credentialsProvider: @escaping () async -> APIRequestCredentials? = {
             await ActivityPushTokenService.shared.apiRequestCredentials()
         },
         retryLimit: Int = 3,
         retryDelay: @escaping (Int) async -> Void = { attempt in
             try? await Task.sleep(for: .seconds(min(300, 2 << attempt)))
         }) {
        self.session = session
        self.endpoint = endpoint ?? Self.defaultTrainInfoEndpoint()
        self.credentialsProvider = credentialsProvider
        self.retryLimit = max(1, retryLimit)
        self.retryDelay = retryDelay
    }

    func getTrainStationInfo(departureDate: String, departureStation: String,
                             trainNo: String) async throws -> TrainStationInfoResponse {
        let date = departureDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let station = departureStation.trimmingCharacters(in: .whitespacesAndNewlines)
        let train = trainNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidDate(date), !station.isEmpty, !train.isEmpty, let endpoint else {
            logger.warning("Station info request skipped: invalid ticket fields or endpoint")
            throw TrainStationInfoAPIError.invalidParameters
        }
        guard let credentials = await credentialsProvider() else {
            logger.warning("Station info request skipped: API credentials unavailable")
            throw TrainStationInfoAPIError.invalidParameters
        }
        let request = try Self.trainStationInfoRequest(
            departureDate: date, departureStation: station, trainNo: train,
            endpoint: endpoint, credentials: credentials)

        var attempt = 0
        while true {
            do {
                let (body, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TrainStationInfoAPIError.invalidResponse
                }
                let decoded = try? JSONDecoder().decode(TrainStationInfoResponse.self, from: body)
                guard httpResponse.statusCode == 200 else {
                    let error = TrainStationInfoAPIError.httpStatus(httpResponse.statusCode,
                                                                    code: decoded?.code)
                    if httpResponse.statusCode == 401 || decoded?.code == 114 {
                        await ActivityPushTokenService.shared.retryAfterAPIUnauthorized()
                    }
                    if error.isRetryable && attempt + 1 < retryLimit {
                        await retryDelay(attempt)
                        attempt += 1
                        continue
                    }
                    throw error
                }
                guard let decoded else { throw TrainStationInfoAPIError.invalidResponse }
                guard decoded.code == 0 else {
                    throw TrainStationInfoAPIError.business(code: decoded.code, message: decoded.err)
                }
                return decoded
            } catch let error as TrainStationInfoAPIError {
                if error.isRetryable && attempt + 1 < retryLimit {
                    await retryDelay(attempt)
                    attempt += 1
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
    }

    nonisolated static func trainStationInfoRequest(
        departureDate: String, departureStation: String, trainNo: String,
        endpoint: URL, credentials: APIRequestCredentials,
        packageName: String = Bundle.main.bundleIdentifier ?? "com.clenson.wristtrip",
        version: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")) throws -> URLRequest {
        let date = departureDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let station = departureStation.trimmingCharacters(in: .whitespacesAndNewlines)
        let train = trainNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDate(date), !station.isEmpty, !train.isEmpty else {
            throw TrainStationInfoAPIError.invalidParameters
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(packageName, forHTTPHeaderField: "packageName")
        request.setValue(version, forHTTPHeaderField: "version")
        request.setValue(credentials.token, forHTTPHeaderField: "token")
        request.setValue(credentials.userLoginToken ?? "", forHTTPHeaderField: "userLoginToken")
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "departureDate": date,
            "departureStation": station,
            "trainNo": train
        ], options: [])
        return request
    }

    nonisolated static func defaultTrainInfoEndpoint() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WristTripScheduleURL") as? String,
              var components = URLComponents(string: raw), components.scheme == "https",
              components.host != nil else { return nil }
        components.path = "/api/apns/train-info"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    nonisolated static func isValidDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }
}

typealias TrainStationInfoAPIClient = APIClient
