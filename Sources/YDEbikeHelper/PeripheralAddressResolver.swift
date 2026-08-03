import CoreBluetooth
import Foundation

/// CoreBluetooth 的公开 API 不提供 BLE 地址。macOS 本地版本会尝试读取系统
/// 当前保留的 BDAddress；iOS 版本始终返回 nil，并使用广播候选或手动输入。
enum PeripheralAddressResolver {
    static func address(for peripheral: CBPeripheral) -> String? {
#if os(macOS)
        let selector = NSSelectorFromString("BDAddress")
        guard
            peripheral.responds(to: selector),
            let value = peripheral.perform(selector)?.takeUnretainedValue()
        else {
            return nil
        }

        let rawAddress: String
        if let string = value as? String {
            rawAddress = string
        } else {
            rawAddress = String(describing: value)
        }

        guard let normalized = try? YDEbikeProtocol.normalizedMAC(rawAddress) else {
            return nil
        }
        let compact = normalized.replacingOccurrences(of: ":", with: "")
        guard compact != "000000000000", compact != "FFFFFFFFFFFF" else {
            return nil
        }
        return normalized
#else
        nil
#endif
    }
}
