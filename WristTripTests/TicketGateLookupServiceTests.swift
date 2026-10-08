import Foundation
import XCTest
@testable import WristTrip

final class TicketGateLookupServiceTests: XCTestCase {
    func testExtractsStringTrainPlatform() throws {
        let response = try jsonObject("""
        {"data":{"trainPlatform":"A1"}}
        """)

        XCTAssertEqual(TicketGateLookupService.extractGates(from: response), ["A1"])
    }

    func testExtractsArrayTrainPlatformAndDeduplicates() throws {
        let response = try jsonObject("""
        {"data":{"trainPlatform":["B2","B3","B2"]}}
        """)

        XCTAssertEqual(TicketGateLookupService.extractGates(from: response), ["B2", "B3"])
    }

    func testExtractsObjectTrainPlatform() throws {
        let response = try jsonObject("""
        {"data":{"trainPlatform":{"name":"C4"}}}
        """)

        XCTAssertEqual(TicketGateLookupService.extractGates(from: response), ["C4"])
    }

    func testRemovesGateLabelsAndOnSiteAnnouncementPrefix() throws {
        let response = try jsonObject("""
        {"data":{"trainPlatform":"检票口：D5、D6；以现场公告为准"}}
        """)

        XCTAssertEqual(TicketGateLookupService.extractGates(from: response), ["D5", "D6"])
    }

    func testEmptyResponseProducesNoGates() throws {
        let emptyObject = try jsonObject("{}")
        let emptyPlatform = try jsonObject("""
        {"data":{"trainPlatform":""}}
        """)

        XCTAssertTrue(TicketGateLookupService.extractGates(from: emptyObject).isEmpty)
        XCTAssertTrue(TicketGateLookupService.extractGates(from: emptyPlatform).isEmpty)
        XCTAssertEqual(TicketGateLookupError.noGate.errorDescription, "12306 当前没有返回检票口，已保留原值")
    }

    private func jsonObject(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8), options: [])
    }
}
