import Foundation

enum DeviceConnectionPhase: String, Codable {
    case discovered
    case connecting
    case discovering
    case authenticating
    case ready
    case disconnecting
    case failed

    var title: String {
        switch self {
        case .discovered: return "未连接"
        case .connecting: return "连接中"
        case .discovering: return "发现服务"
        case .authenticating: return "认证中"
        case .ready: return "已就绪"
        case .disconnecting: return "断开中"
        case .failed: return "连接失败"
        }
    }
}

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var phase: DeviceConnectionPhase
    var lastSeen: Date
    var advertisedServices: [String]
    var advertisement: BLEAdvertisementSnapshot

    var isConnected: Bool {
        [.discovering, .authenticating, .ready, .disconnecting].contains(phase)
    }
}

enum MACCandidateConfidence: Int, Equatable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

struct MACAddressCandidate: Identifiable, Equatable {
    var id: String { "\(address)|\(source)" }
    let address: String
    let source: String
    let confidence: MACCandidateConfidence
}

struct BLEAdvertisementSnapshot: Equatable {
    var localName: String?
    var systemAddress: String?
    var manufacturerData: Data?
    var serviceData: [String: Data]
    var txPower: Int?
    var isConnectable: Bool?
    var solicitedServices: [String]
    var overflowServices: [String]
    var macCandidates: [MACAddressCandidate]

    static let empty = BLEAdvertisementSnapshot(
        localName: nil,
        systemAddress: nil,
        manufacturerData: nil,
        serviceData: [:],
        txPower: nil,
        isConnectable: nil,
        solicitedServices: [],
        overflowServices: []
    )

    init(
        localName: String?,
        systemAddress: String? = nil,
        manufacturerData: Data?,
        serviceData: [String: Data],
        txPower: Int?,
        isConnectable: Bool?,
        solicitedServices: [String],
        overflowServices: [String]
    ) {
        self.localName = localName
        self.systemAddress = systemAddress
        self.manufacturerData = manufacturerData
        self.serviceData = serviceData
        self.txPower = txPower
        self.isConnectable = isConnectable
        self.solicitedServices = solicitedServices
        self.overflowServices = overflowServices
        macCandidates = MACCandidateExtractor.candidates(
            systemAddress: systemAddress,
            localName: localName,
            manufacturerData: manufacturerData,
            serviceData: serviceData
        )
    }

    func merging(_ newer: BLEAdvertisementSnapshot) -> BLEAdvertisementSnapshot {
        var combinedServiceData = serviceData
        for (uuid, data) in newer.serviceData {
            combinedServiceData[uuid] = data
        }

        return BLEAdvertisementSnapshot(
            localName: newer.localName ?? localName,
            systemAddress: newer.systemAddress ?? systemAddress,
            manufacturerData: newer.manufacturerData ?? manufacturerData,
            serviceData: combinedServiceData,
            txPower: newer.txPower ?? txPower,
            isConnectable: newer.isConnectable ?? isConnectable,
            solicitedServices: orderedUnion(solicitedServices, newer.solicitedServices),
            overflowServices: orderedUnion(overflowServices, newer.overflowServices)
        )
    }

    private func orderedUnion(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        return (lhs + rhs).filter { seen.insert($0).inserted }
    }
}

enum MACCandidateExtractor {
    static func candidates(
        systemAddress: String? = nil,
        localName: String?,
        manufacturerData: Data?,
        serviceData: [String: Data]
    ) -> [MACAddressCandidate] {
        var result: [MACAddressCandidate] = []
        var seenAddresses = Set<String>()

        func append(
            _ bytes: ArraySlice<UInt8>,
            source: String,
            confidence: MACCandidateConfidence,
            includeReversed: Bool
        ) {
            guard bytes.count == 6 else { return }
            let values = Array(bytes)
            appendAddress(values, source: source, confidence: confidence)
            if includeReversed {
                appendAddress(
                    values.reversed(),
                    source: "\(source)，逆序",
                    confidence: .low
                )
            }
        }

        func appendAddress<S: Sequence>(
            _ bytes: S,
            source: String,
            confidence: MACCandidateConfidence
        ) where S.Element == UInt8 {
            let values = Array(bytes)
            guard
                values.count == 6,
                !values.allSatisfy({ $0 == 0x00 }),
                !values.allSatisfy({ $0 == 0xFF })
            else {
                return
            }

            let address = values.map { String(format: "%02X", $0) }.joined(separator: ":")
            guard seenAddresses.insert(address).inserted else { return }
            result.append(
                MACAddressCandidate(
                    address: address,
                    source: source,
                    confidence: confidence
                )
            )
        }

        if let systemAddress,
            let normalized = try? YDEbikeProtocol.normalizedMAC(systemAddress)
        {
            let bytes = normalized
                .split(separator: ":")
                .compactMap { UInt8($0, radix: 16) }
            appendAddress(
                bytes,
                source: "macOS 系统 BDAddress（私有接口）",
                confidence: .high
            )
        }

        if
            let localName,
            let manufacturerData,
            let suffix = ydNameSuffixBytes(localName)
        {
            let bytes = [UInt8](manufacturerData)
            if bytes.count >= 6 {
                for index in 2 ... (bytes.count - 4) {
                    guard Array(bytes[index ..< index + 4]) == suffix else { continue }
                    append(
                        bytes[index - 2 ..< index + 4],
                        source: "YD 名称后缀与厂商数据匹配",
                        confidence: .high,
                        includeReversed: true
                    )
                }
            }
        }

        if let localName, let address = addressEmbeddedInName(localName) {
            appendAddress(
                address,
                source: "设备名",
                confidence: .high
            )
        }

        if let manufacturerData {
            let bytes = [UInt8](manufacturerData)
            if bytes.count == 6 {
                append(
                    bytes[0..<6],
                    source: "厂商数据完整值",
                    confidence: .medium,
                    includeReversed: true
                )
            } else if bytes.count >= 8 {
                append(
                    bytes[2..<8],
                    source: "厂商数据（跳过 2 字节公司 ID）",
                    confidence: .medium,
                    includeReversed: true
                )
                if bytes.count > 8 {
                    append(
                        bytes.suffix(6),
                        source: "厂商数据末 6 字节",
                        confidence: .low,
                        includeReversed: true
                    )
                }
            }
        }

        for (uuid, data) in serviceData.sorted(by: { $0.key < $1.key }) {
            let bytes = [UInt8](data)
            guard bytes.count >= 6 else { continue }
            append(
                bytes.prefix(6),
                source: "Service Data \(uuid) 前 6 字节",
                confidence: .low,
                includeReversed: true
            )
            if bytes.count > 6 {
                append(
                    bytes.suffix(6),
                    source: "Service Data \(uuid) 末 6 字节",
                    confidence: .low,
                    includeReversed: true
                )
            }
        }

        return result.sorted {
            if $0.confidence.rawValue != $1.confidence.rawValue {
                return $0.confidence.rawValue > $1.confidence.rawValue
            }
            let lhsIsSystem = $0.source.hasPrefix("macOS 系统 BDAddress")
            let rhsIsSystem = $1.source.hasPrefix("macOS 系统 BDAddress")
            if lhsIsSystem != rhsIsSystem {
                return lhsIsSystem
            }
            return $0.address < $1.address
        }
    }

    private static func addressEmbeddedInName(_ name: String) -> [UInt8]? {
        let pattern = #"(?i)(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}|[0-9A-F]{12}$"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: name,
                range: NSRange(name.startIndex..., in: name)
            ),
            let range = Range(match.range, in: name)
        else {
            return nil
        }

        let compact = name[range].filter(\.isHexDigit)
        guard compact.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = compact.startIndex
        while index < compact.endIndex {
            let end = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<end], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = end
        }
        return bytes
    }

    private static func ydNameSuffixBytes(_ name: String) -> [UInt8]? {
        let uppercased = name.uppercased()
        guard uppercased.hasPrefix("YD"), uppercased.count == 10 else {
            return nil
        }

        let suffix = uppercased.dropFirst(2)
        guard suffix.count == 8, suffix.allSatisfy(\.isHexDigit) else {
            return nil
        }

        var bytes: [UInt8] = []
        var index = suffix.startIndex
        while index < suffix.endIndex {
            let end = suffix.index(index, offsetBy: 2)
            guard let byte = UInt8(suffix[index ..< end], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = end
        }
        return bytes
    }
}

enum BLELogDirection: String {
    case system = "SYS"
    case sent = "TX"
    case received = "RX"
    case error = "ERR"
}

struct BLELogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: BLELogDirection
    let message: String
    let data: Data?
}

extension Data {
    var spacedHex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
