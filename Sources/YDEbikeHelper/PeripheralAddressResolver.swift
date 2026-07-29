import CoreBluetooth
import Foundation

/// CoreBluetooth 的公开 API 不提供 BLE 地址，但当前 macOS 的 CBPeripheral
/// 内部保留了 NSString 类型的 BDAddress。本地调试版本在运行时安全探测它；
/// 若系统移除该选择器，会自动退回广播候选/手动输入，不会崩溃。
enum PeripheralAddressResolver {
    static func address(for peripheral: CBPeripheral) -> String? {
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
    }
}
