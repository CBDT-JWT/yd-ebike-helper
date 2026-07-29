import Foundation

enum YDEbikeProtocolError: LocalizedError, Equatable {
    case invalidMACAddress
    case challengeTooShort
    case invalidHex

    var errorDescription: String? {
        switch self {
        case .invalidMACAddress:
            return "MAC 地址必须包含 12 个十六进制字符，例如 A1:B2:C3:D4:E5:F6。"
        case .challengeTooShort:
            return "认证挑战值少于 3 字节。"
        case .invalidHex:
            return "HEX 数据格式无效，请输入成对的十六进制字符。"
        }
    }
}

enum YDEbikeProtocol {
    static let authenticationService = "E7810B92-73AE-499D-8C15-FAA9AEF0C3F2"
    static let authenticationReadWriteCharacteristic = "BEF8E7E0-9C21-4C9E-B632-BD58C1009F9F"
    static let authenticationNotifyCharacteristic = "BEF8E7E1-9C21-4C9E-B632-BD58C1009F9F"

    static let commandService = "E7810BD2-73AE-499D-8C15-FAA9AEF0C3F2"
    static let commandNotifyCharacteristic = "BEF8E820-9C21-4C9E-B632-BD58C1009F9F"
    static let commandWriteCharacteristic = "BEF8E821-9C21-4C9E-B632-BD58C1009F9F"

    static func normalizedMAC(_ value: String) throws -> String {
        let hex = value.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12 else {
            throw YDEbikeProtocolError.invalidMACAddress
        }
        return stride(from: 0, to: 12, by: 2)
            .map { index in
                let start = hex.index(hex.startIndex, offsetBy: index)
                let end = hex.index(start, offsetBy: 2)
                return String(hex[start..<end])
            }
            .joined(separator: ":")
    }

    static func authenticationPacket(
        challenge: Data,
        macAddress: String,
        hour: Int,
        minute: Int,
        second: Int
    ) throws -> Data {
        guard challenge.count >= 3 else {
            throw YDEbikeProtocolError.challengeTooShort
        }

        let normalized = try normalizedMAC(macAddress)
        let compactMAC = normalized.replacingOccurrences(of: ":", with: "")
        guard
            let firstHalf = Int(compactMAC.prefix(6), radix: 16),
            let secondHalf = Int(compactMAC.suffix(6), radix: 16)
        else {
            throw YDEbikeProtocolError.invalidMACAddress
        }

        let bytes = [UInt8](challenge)
        let challengeValue = (Int(bytes[0]) << 16) | (Int(bytes[1]) << 8) | Int(bytes[2])
        let timeValue = ((hour & 0xFF) << 16) | ((minute & 0xFF) << 8) | (second & 0xFF)
        let combined = challengeValue | timeValue
        let firstKey = combined ^ firstHalf
        let secondKey = combined ^ secondHalf

        return Data(
            bytes24(combined)
                + bytes24(firstKey)
                + bytes24(secondKey)
                + [0x41, 0x05, 0x01, 0x10, 0x55]
        )
    }

    static func authenticationPacket(
        challenge: Data,
        macAddress: String,
        date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Data {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return try authenticationPacket(
            challenge: challenge,
            macAddress: macAddress,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0
        )
    }

    static func debugPacket() -> Data {
        checksummed([
            0x59, 0x44, 0x39, 0x08, 0x55, 0xFD, 0xFE, 0xFE,
            0xFE, 0xFE, 0xFE, 0xFF, 0x00, 0x4B, 0x4A
        ])
    }

    static func restorePacket() -> Data {
        checksummed([
            0x59, 0x44, 0x39, 0x08, 0x00, 0xFC, 0xFD, 0xFD,
            0xFD, 0xFD, 0xFD, 0xFF, 0x00, 0x4B, 0x4A
        ])
    }

    static func volumePacket(level: Int) -> Data {
        let value: UInt8
        switch level {
        case 4: value = 0x3F
        case 6: value = 0x5F
        case 7: value = 0x7F
        default: value = 0x3F
        }

        var packet: [UInt8] = [0x59, 0x44, 0x3E, 0x31, 0x01, 0x00, 0x01, 0x01]
        packet.append(contentsOf: repeatElement(0xFF, count: 44))
        packet.append(contentsOf: [value, 0x00, 0x4B, 0x4A])
        return checksummed(packet)
    }

    static func commandResponseCode(from data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 40, bytes[2] == 0x2A else {
            return nil
        }
        return Int((bytes[39] >> 3) & 0x03)
    }

    static func parseHex(_ input: String) throws -> Data {
        let compact = input
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace && $0 != ":" && $0 != "-" && $0 != "," }

        guard !compact.isEmpty, compact.count.isMultiple(of: 2) else {
            throw YDEbikeProtocolError.invalidHex
        }

        var result = Data()
        var index = compact.startIndex
        while index < compact.endIndex {
            let end = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<end], radix: 16) else {
                throw YDEbikeProtocolError.invalidHex
            }
            result.append(byte)
            index = end
        }
        return result
    }

    private static func bytes24(_ value: Int) -> [UInt8] {
        [
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    private static func checksummed(_ source: [UInt8]) -> Data {
        var packet = source
        guard packet.count >= 5 else {
            return Data(packet)
        }

        let checksumIndex = Int(packet[3]) + 4
        guard checksumIndex < packet.count else {
            return Data(packet)
        }

        packet[checksumIndex] = packet[2..<checksumIndex].reduce(UInt8(0)) {
            $0 &+ $1
        }
        return Data(packet)
    }
}
