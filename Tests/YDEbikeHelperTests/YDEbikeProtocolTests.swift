import XCTest
@testable import YDEbikeHelper

final class YDEbikeProtocolTests: XCTestCase {
    func testMACNormalization() throws {
        XCTAssertEqual(
            try YDEbikeProtocol.normalizedMAC("a1-b2-c3-d4-e5-f6"),
            "A1:B2:C3:D4:E5:F6"
        )
        XCTAssertThrowsError(try YDEbikeProtocol.normalizedMAC("1234"))
    }

    func testAuthenticationPacketOutput() throws {
        let packet = try YDEbikeProtocol.authenticationPacket(
            challenge: Data([0x12, 0x34, 0x56]),
            macAddress: "A1:B2:C3:D4:E5:F6",
            hour: 10,
            minute: 20,
            second: 30
        )

        XCTAssertEqual(packet.count, 14)
        XCTAssertEqual(
            packet,
            Data([
                0x1A, 0x34, 0x5E,
                0xBB, 0x86, 0x9D,
                0xCE, 0xD1, 0xA8,
                0x41, 0x05, 0x01, 0x10, 0x55
            ])
        )
    }

    func testControlPacketsAndChecksums() {
        let debug = [UInt8](YDEbikeProtocol.debugPacket())
        XCTAssertEqual(debug.count, 15)
        XCTAssertEqual(debug.prefix(4), [0x59, 0x44, 0x39, 0x08])
        XCTAssertEqual(debug[12], debug[2..<12].reduce(UInt8(0), &+))
        XCTAssertEqual(debug.suffix(2), [0x4B, 0x4A])

        let restore = [UInt8](YDEbikeProtocol.restorePacket())
        XCTAssertEqual(restore.count, 15)
        XCTAssertEqual(restore[12], restore[2..<12].reduce(UInt8(0), &+))

        for level in [4, 6, 7] {
            let volume = [UInt8](YDEbikeProtocol.volumePacket(level: level))
            XCTAssertEqual(volume.count, 56)
            XCTAssertEqual(volume[53], volume[2..<53].reduce(UInt8(0), &+))
            XCTAssertEqual(volume.suffix(2), [0x4B, 0x4A])
        }
        XCTAssertEqual([UInt8](YDEbikeProtocol.volumePacket(level: 4))[52], 0x3F)
        XCTAssertEqual([UInt8](YDEbikeProtocol.volumePacket(level: 6))[52], 0x5F)
        XCTAssertEqual([UInt8](YDEbikeProtocol.volumePacket(level: 7))[52], 0x7F)
    }

    func testCommandResponseParser() {
        var response = Data(repeating: 0, count: 40)
        response[2] = 0x2A
        response[39] = 0x08
        XCTAssertEqual(YDEbikeProtocol.commandResponseCode(from: response), 1)
        XCTAssertNil(YDEbikeProtocol.commandResponseCode(from: Data([0x59, 0x44])))
    }

    func testHexParser() throws {
        XCTAssertEqual(
            try YDEbikeProtocol.parseHex("0x59 44:3E-31"),
            Data([0x59, 0x44, 0x3E, 0x31])
        )
        XCTAssertThrowsError(try YDEbikeProtocol.parseHex("ABC"))
    }

    func testMACCandidateFromDeviceName() {
        let candidates = MACCandidateExtractor.candidates(
            localName: "YD-A1B2C3D4E5F6",
            manufacturerData: nil,
            serviceData: [:]
        )

        XCTAssertEqual(candidates.first?.address, "A1:B2:C3:D4:E5:F6")
        XCTAssertEqual(candidates.first?.confidence, .high)
        XCTAssertEqual(candidates.first?.source, "设备名")
    }

    func testSystemAddressIsHighestConfidenceCandidate() {
        let candidates = MACCandidateExtractor.candidates(
            systemAddress: "12:34:56:78:9A:BC",
            localName: "YD-A1B2C3D4E5F6",
            manufacturerData: nil,
            serviceData: [:]
        )

        XCTAssertEqual(candidates.first?.address, "12:34:56:78:9A:BC")
        XCTAssertEqual(candidates.first?.confidence, .high)
        XCTAssertEqual(candidates.first?.source, "macOS 系统 BDAddress（私有接口）")
    }

    func testMACCandidatesFromManufacturerDataIncludeBothOrders() {
        let candidates = MACCandidateExtractor.candidates(
            localName: "YD-Test",
            manufacturerData: Data([0x34, 0x12, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]),
            serviceData: [:]
        )

        XCTAssertTrue(candidates.contains { $0.address == "A1:B2:C3:D4:E5:F6" })
        XCTAssertTrue(candidates.contains { $0.address == "F6:E5:D4:C3:B2:A1" })
    }

    func testYDNameSuffixLocatesFullMACInsideManufacturerData() {
        let candidates = MACCandidateExtractor.candidates(
            localName: "YD5C034643",
            manufacturerData: Data([
                0xFF, 0xFF, 0xFF, 0xFF,
                0xC1, 0x28, 0x5C, 0x03, 0x46, 0x43,
                0xE0, 0x0B, 0x1B, 0x02
            ]),
            serviceData: [:]
        )

        XCTAssertEqual(candidates.first?.address, "C1:28:5C:03:46:43")
        XCTAssertEqual(candidates.first?.confidence, .high)
        XCTAssertEqual(candidates.first?.source, "YD 名称后缀与厂商数据匹配")
        XCTAssertTrue(candidates.contains { $0.address == "43:46:03:5C:28:C1" })
    }

    func testMACCandidateRejectsEmptyBinaryValues() {
        XCTAssertTrue(
            MACCandidateExtractor.candidates(
                localName: nil,
                manufacturerData: Data(repeating: 0, count: 6),
                serviceData: [:]
            ).isEmpty
        )
    }

    func testAdvertisementMergeRetainsEarlierManufacturerData() {
        let first = BLEAdvertisementSnapshot(
            localName: "YD-Test",
            systemAddress: "12:34:56:78:9A:BC",
            manufacturerData: Data([0x34, 0x12, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]),
            serviceData: [:],
            txPower: nil,
            isConnectable: true,
            solicitedServices: [],
            overflowServices: []
        )
        let later = BLEAdvertisementSnapshot(
            localName: nil,
            manufacturerData: nil,
            serviceData: ["FFF0": Data([0x01, 0x02])],
            txPower: -4,
            isConnectable: nil,
            solicitedServices: [],
            overflowServices: []
        )

        let merged = first.merging(later)
        XCTAssertEqual(merged.manufacturerData, first.manufacturerData)
        XCTAssertEqual(merged.systemAddress, "12:34:56:78:9A:BC")
        XCTAssertEqual(merged.txPower, -4)
        XCTAssertEqual(merged.serviceData["FFF0"], Data([0x01, 0x02]))
        XCTAssertTrue(merged.macCandidates.contains { $0.address == "A1:B2:C3:D4:E5:F6" })
    }
}
