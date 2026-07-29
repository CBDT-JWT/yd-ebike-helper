import Combine
import CoreBluetooth
import Foundation

final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var logs: [BLELogEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothState = "正在初始化蓝牙"
    @Published private(set) var connectedDeviceID: UUID?
    @Published var deviceNamePrefix = "YD"
    @Published var minimumRSSI = -60
    @Published var lastError: String?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var scanStopWorkItem: DispatchWorkItem?
    private var activePeripheral: CBPeripheral?
    private var activeMACAddress: String?
    private var authReadWriteCharacteristic: CBCharacteristic?
    private var authNotifyCharacteristic: CBCharacteristic?
    private var commandWriteCharacteristic: CBCharacteristic?
    private var commandNotifyCharacteristic: CBCharacteristic?
    private var authenticationStarted = false
    private var authenticationReadScheduled = false
    private var authenticationCompleted = false

    private struct PendingWrite {
        let data: Data
        let characteristic: CBCharacteristic
        let label: String
        let completesAuthentication: Bool
    }

    private var writeQueue: [PendingWrite] = []
    private var activeWrite: PendingWrite?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var visibleDevices: [DiscoveredDevice] {
        devices.filter { device in
            let prefixMatches = deviceNamePrefix.isEmpty
                || device.name.range(
                    of: deviceNamePrefix,
                    options: [.anchored, .caseInsensitive]
                ) != nil
            return prefixMatches && device.rssi >= minimumRSSI
        }
    }

    var activeDevice: DiscoveredDevice? {
        guard let id = connectedDeviceID else { return nil }
        return devices.first { $0.id == id }
    }

    func savedMACAddress(for id: UUID) -> String {
        UserDefaults.standard.string(forKey: macDefaultsKey(id)) ?? ""
    }

    func preferredMACCandidate(for id: UUID) -> MACAddressCandidate? {
        devices
            .first(where: { $0.id == id })?
            .advertisement
            .macCandidates
            .first(where: { $0.confidence == .high })
    }

    func systemMACAddress(for id: UUID) -> String? {
        devices
            .first(where: { $0.id == id })?
            .advertisement
            .systemAddress
    }

    func saveMACAddress(_ address: String, for id: UUID) throws -> String {
        let normalized = try YDEbikeProtocol.normalizedMAC(address)
        UserDefaults.standard.set(normalized, forKey: macDefaultsKey(id))
        return normalized
    }

    func refreshScan() {
        if let peripheral = activePeripheral {
            updatePhase(.disconnecting, for: peripheral.identifier)
            central.cancelPeripheralConnection(peripheral)
        }
        devices.removeAll()
        peripherals.removeAll()
        startScan()
    }

    func startScan() {
        guard central.state == .poweredOn else {
            lastError = bluetoothState
            appendLog(.error, "无法扫描：\(bluetoothState)")
            return
        }

        scanStopWorkItem?.cancel()
        isScanning = true
        lastError = nil
        appendLog(.system, "开始扫描 BLE 设备（5 秒）")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        let workItem = DispatchWorkItem { [weak self] in
            self?.stopScan()
        }
        scanStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    func stopScan() {
        scanStopWorkItem?.cancel()
        scanStopWorkItem = nil
        if isScanning {
            central.stopScan()
            isScanning = false
            appendLog(.system, "扫描结束，发现 \(visibleDevices.count) 个匹配设备")
        }
    }

    func connect(to id: UUID, macAddress: String) {
        guard let peripheral = peripherals[id] else {
            reportError("设备已离开扫描范围，请刷新后重试。")
            return
        }

        do {
            let bestAddress = systemMACAddress(for: id)
                ?? preferredMACCandidate(for: id)?.address
                ?? macAddress
            activeMACAddress = try saveMACAddress(bestAddress, for: id)
        } catch {
            reportError(error.localizedDescription)
            return
        }

        stopScan()
        resetProtocolState()
        activePeripheral = peripheral
        connectedDeviceID = id
        updatePhase(.connecting, for: id)
        appendLog(.system, "连接 \(displayName(for: peripheral))，认证 MAC \(activeMACAddress ?? "")")
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = activePeripheral else { return }
        updatePhase(.disconnecting, for: peripheral.identifier)
        appendLog(.system, "正在断开 \(displayName(for: peripheral))")
        central.cancelPeripheralConnection(peripheral)
    }

    func sendDebugCommand() {
        sendCommand(YDEbikeProtocol.debugPacket(), label: "调试")
    }

    func sendRestoreCommand() {
        sendCommand(YDEbikeProtocol.restorePacket(), label: "还原")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.sendCommand(YDEbikeProtocol.volumePacket(level: 4), label: "还原后音量 4")
        }
    }

    func sendVolume(_ level: Int) {
        sendCommand(YDEbikeProtocol.volumePacket(level: level), label: "音量 \(level)")
    }

    func sendCustomHex(_ input: String) {
        do {
            sendCommand(try YDEbikeProtocol.parseHex(input), label: "自定义 HEX")
        } catch {
            reportError(error.localizedDescription)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func sendCommand(_ data: Data, label: String) {
        guard authenticationCompleted, let characteristic = commandWriteCharacteristic else {
            reportError("设备尚未完成认证，不能发送指令。")
            return
        }
        enqueueWrite(data, to: characteristic, label: label)
    }

    private func beginAuthenticationIfPossible() {
        guard
            !authenticationStarted,
            let peripheral = activePeripheral,
            let readWrite = authReadWriteCharacteristic,
            let notify = authNotifyCharacteristic,
            commandWriteCharacteristic != nil
        else {
            return
        }

        authenticationStarted = true
        updatePhase(.authenticating, for: peripheral.identifier)
        appendLog(.system, "服务已就绪，先订阅认证通知")

        if notify.isNotifying {
            scheduleAuthenticationRead(
                peripheral: peripheral,
                characteristic: readWrite
            )
        } else if notify.properties.contains(.notify) || notify.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: notify)

            // 某些外设不会回调通知状态。超时后仍继续认证。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak peripheral] in
                guard
                    let self,
                    let peripheral,
                    self.activePeripheral === peripheral,
                    let readWrite = self.authReadWriteCharacteristic
                else {
                    return
                }
                self.scheduleAuthenticationRead(
                    peripheral: peripheral,
                    characteristic: readWrite
                )
            }
        } else {
            appendLog(.error, "认证通知特征不支持 Notify/Indicate，继续尝试读取挑战值")
            scheduleAuthenticationRead(
                peripheral: peripheral,
                characteristic: readWrite
            )
        }
    }

    private func scheduleAuthenticationRead(
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
    ) {
        guard !authenticationReadScheduled else { return }
        authenticationReadScheduled = true
        appendLog(.system, "认证通知就绪，等待 400 ms")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak peripheral] in
            guard
                let self,
                let peripheral,
                self.activePeripheral === peripheral
            else {
                return
            }

            self.appendLog(.system, "读取连接 RSSI")
            peripheral.readRSSI()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak peripheral] in
                guard
                    let self,
                    let peripheral,
                    self.activePeripheral === peripheral
                else {
                    return
                }
                self.appendLog(.system, "读取认证挑战值")
                peripheral.readValue(for: characteristic)
            }
        }
    }

    private func authenticate(challenge: Data) {
        guard
            let peripheral = activePeripheral,
            let macAddress = activeMACAddress,
            let characteristic = authReadWriteCharacteristic
        else {
            reportError("认证上下文不完整。")
            return
        }

        do {
            let packet = try YDEbikeProtocol.authenticationPacket(
                challenge: challenge,
                macAddress: macAddress
            )
            enqueueWrite(
                packet,
                to: characteristic,
                label: "认证响应",
                completesAuthentication: true
            )
            appendLog(.system, "已生成认证响应")
        } catch {
            updatePhase(.failed, for: peripheral.identifier)
            reportError(error.localizedDescription)
        }
    }

    private func enqueueWrite(
        _ data: Data,
        to characteristic: CBCharacteristic,
        label: String,
        completesAuthentication: Bool = false
    ) {
        writeQueue.append(
            PendingWrite(
                data: data,
                characteristic: characteristic,
                label: label,
                completesAuthentication: completesAuthentication
            )
        )
        drainWriteQueue()
    }

    private func drainWriteQueue() {
        guard
            activeWrite == nil,
            !writeQueue.isEmpty,
            let peripheral = activePeripheral
        else {
            return
        }

        let next = writeQueue.removeFirst()
        let writeType: CBCharacteristicWriteType = next.characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        let maximum = peripheral.maximumWriteValueLength(for: writeType)
        guard next.data.count <= maximum else {
            reportError(
                "\(next.label) 共 \(next.data.count) 字节，超过当前链路单次写入上限 \(maximum) 字节。"
            )
            drainWriteQueue()
            return
        }

        activeWrite = next
        appendLog(.sent, next.label, data: next.data)
        peripheral.writeValue(next.data, for: next.characteristic, type: writeType)

        if writeType == .withoutResponse {
            finishActiveWrite(error: nil)
        }
    }

    private func finishActiveWrite(error: Error?) {
        guard let write = activeWrite else { return }
        activeWrite = nil

        if let error {
            reportError("\(write.label)写入失败：\(error.localizedDescription)")
        } else {
            appendLog(.system, "\(write.label)写入成功")
            if write.completesAuthentication, let peripheral = activePeripheral {
                authenticationCompleted = true
                updatePhase(.ready, for: peripheral.identifier)
                appendLog(.system, "认证响应已写入，设备可开始调试")
                peripheral.readRSSI()
            }
        }
        drainWriteQueue()
    }

    private func resetProtocolState() {
        authReadWriteCharacteristic = nil
        authNotifyCharacteristic = nil
        commandWriteCharacteristic = nil
        commandNotifyCharacteristic = nil
        authenticationStarted = false
        authenticationReadScheduled = false
        authenticationCompleted = false
        writeQueue.removeAll()
        activeWrite = nil
    }

    private func updateDevice(
        id: UUID,
        name: String,
        rssi: Int,
        advertisedServices: [String],
        advertisement: BLEAdvertisementSnapshot
    ) {
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].name = name
            devices[index].rssi = rssi
            devices[index].lastSeen = Date()
            devices[index].advertisedServices = Array(
                Set(devices[index].advertisedServices + advertisedServices)
            ).sorted()
            devices[index].advertisement = devices[index].advertisement.merging(advertisement)
        } else {
            devices.append(
                DiscoveredDevice(
                    id: id,
                    name: name,
                    rssi: rssi,
                    phase: .discovered,
                    lastSeen: Date(),
                    advertisedServices: advertisedServices,
                    advertisement: advertisement
                )
            )
        }

        devices.sort { lhs, rhs in
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected
            }
            return lhs.rssi > rhs.rssi
        }
        if devices.count > 50 {
            devices.removeLast(devices.count - 50)
        }
    }

    private func updateSystemAddress(_ address: String, for id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let addressUpdate = BLEAdvertisementSnapshot(
            localName: nil,
            systemAddress: address,
            manufacturerData: nil,
            serviceData: [:],
            txPower: nil,
            isConnectable: nil,
            solicitedServices: [],
            overflowServices: []
        )
        devices[index].advertisement = devices[index].advertisement.merging(addressUpdate)
        devices = devices
    }

    private func updatePhase(_ phase: DeviceConnectionPhase, for id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].phase = phase
        devices = devices
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name ?? devices.first(where: { $0.id == peripheral.identifier })?.name ?? "未知设备"
    }

    private func macDefaultsKey(_ id: UUID) -> String {
        "yd-device-mac-\(id.uuidString)"
    }

    private func appendLog(
        _ direction: BLELogDirection,
        _ message: String,
        data: Data? = nil
    ) {
        logs.append(
            BLELogEntry(
                timestamp: Date(),
                direction: direction,
                message: message,
                data: data
            )
        )
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    private func reportError(_ message: String) {
        lastError = message
        appendLog(.error, message)
    }

    private func errorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription) [\(nsError.domain):\(nsError.code)]"
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothState = "蓝牙已开启"
            appendLog(.system, bluetoothState)
            if devices.isEmpty, !isScanning {
                startScan()
            }
        case .poweredOff:
            bluetoothState = "蓝牙已关闭"
            isScanning = false
            appendLog(.error, bluetoothState)
        case .unauthorized:
            bluetoothState = "没有蓝牙权限"
            reportError("请在“系统设置 → 隐私与安全性 → 蓝牙”中允许本应用访问蓝牙。")
        case .unsupported:
            bluetoothState = "此 Mac 不支持 BLE"
            appendLog(.error, bluetoothState)
        case .resetting:
            bluetoothState = "蓝牙正在重置"
        case .unknown:
            bluetoothState = "蓝牙状态未知"
        @unknown default:
            bluetoothState = "未知蓝牙状态"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard RSSI.intValue != 127 else { return }
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = localName ?? peripheral.name ?? "未命名设备"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:])
            .reduce(into: [String: Data]()) { result, item in
                result[item.key.uuidString] = item.value
            }
        let advertisement = BLEAdvertisementSnapshot(
            localName: localName,
            systemAddress: PeripheralAddressResolver.address(for: peripheral),
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceData: serviceData,
            txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue,
            solicitedServices: (
                advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []
            ).map(\.uuidString),
            overflowServices: (
                advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
            ).map(\.uuidString)
        )
        peripherals[peripheral.identifier] = peripheral
        updateDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            advertisedServices: services,
            advertisement: advertisement
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let systemAddress = PeripheralAddressResolver.address(for: peripheral) {
            activeMACAddress = systemAddress
            _ = try? saveMACAddress(systemAddress, for: peripheral.identifier)
            updateSystemAddress(systemAddress, for: peripheral.identifier)
            appendLog(
                .system,
                "macOS 读取到系统 BDAddress \(systemAddress)，将覆盖广播候选用于认证"
            )
        } else {
            appendLog(
                .system,
                "当前系统未提供 BDAddress，继续使用 \(activeMACAddress ?? "手动地址")"
            )
        }
        appendLog(.system, "已连接 \(displayName(for: peripheral))，开始发现 GATT 服务")
        updatePhase(.discovering, for: peripheral.identifier)
        peripheral.delegate = self
        peripheral.discoverServices([
            CBUUID(string: YDEbikeProtocol.authenticationService),
            CBUUID(string: YDEbikeProtocol.commandService)
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        updatePhase(.failed, for: peripheral.identifier)
        reportError(
            "连接失败：\(error.map(errorDescription) ?? "请将设备重新上电后重试")"
        )
        activePeripheral = nil
        connectedDeviceID = nil
        resetProtocolState()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let disconnectedDuringAuthentication = authenticationStarted && !authenticationCompleted
        updatePhase(.discovered, for: peripheral.identifier)
        appendLog(
            error == nil ? .system : .error,
            error == nil
                ? "已断开 \(displayName(for: peripheral))"
                : "连接中断：\(errorDescription(error!))"
        )
        if disconnectedDuringAuthentication {
            appendLog(
                .error,
                "认证完成前断线：请关闭曾连接该设备的 iPhone 蓝牙/控制 App，重新给设备上电后再试。"
            )
        }
        activePeripheral = nil
        connectedDeviceID = nil
        activeMACAddress = nil
        resetProtocolState()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            reportError("发现服务失败：\(error.localizedDescription)")
            return
        }

        let services = peripheral.services ?? []
        appendLog(.system, "发现 \(services.count) 个目标服务")
        for service in services {
            switch service.uuid.uuidString.uppercased() {
            case YDEbikeProtocol.authenticationService:
                peripheral.discoverCharacteristics([
                    CBUUID(string: YDEbikeProtocol.authenticationReadWriteCharacteristic),
                    CBUUID(string: YDEbikeProtocol.authenticationNotifyCharacteristic)
                ], for: service)
            case YDEbikeProtocol.commandService:
                peripheral.discoverCharacteristics([
                    CBUUID(string: YDEbikeProtocol.commandWriteCharacteristic),
                    CBUUID(string: YDEbikeProtocol.commandNotifyCharacteristic)
                ], for: service)
            default:
                continue
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            reportError("发现特征失败：\(error.localizedDescription)")
            return
        }

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid.uuidString.uppercased() {
            case YDEbikeProtocol.authenticationReadWriteCharacteristic:
                authReadWriteCharacteristic = characteristic
            case YDEbikeProtocol.authenticationNotifyCharacteristic:
                authNotifyCharacteristic = characteristic
            case YDEbikeProtocol.commandWriteCharacteristic:
                commandWriteCharacteristic = characteristic
            case YDEbikeProtocol.commandNotifyCharacteristic:
                commandNotifyCharacteristic = characteristic
            default:
                continue
            }
            appendLog(.system, "特征 \(characteristic.uuid.uuidString) 已发现")
        }

        beginAuthenticationIfPossible()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            reportError("读取 \(characteristic.uuid.uuidString) 失败：\(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }

        appendLog(.received, characteristic.uuid.uuidString, data: data)
        switch characteristic.uuid.uuidString.uppercased() {
        case YDEbikeProtocol.authenticationReadWriteCharacteristic:
            if !authenticationCompleted {
                authenticate(challenge: data)
            }
        case YDEbikeProtocol.commandNotifyCharacteristic:
            if let code = YDEbikeProtocol.commandResponseCode(from: data) {
                appendLog(
                    code == 1 ? .system : .error,
                    code == 1 ? "设备返回：操作成功" : "设备返回：操作失败（状态 \(code)）"
                )
            }
        default:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        finishActiveWrite(error: error)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            appendLog(
                .error,
                "订阅 \(characteristic.uuid.uuidString) 失败：\(errorDescription(error))"
            )
        } else {
            appendLog(.system, "已订阅通知 \(characteristic.uuid.uuidString)")
        }

        if characteristic.uuid.uuidString.uppercased()
            == YDEbikeProtocol.authenticationNotifyCharacteristic,
            let readWrite = authReadWriteCharacteristic
        {
            // 即使订阅失败也继续认证，因此这里不因 error 提前退出。
            scheduleAuthenticationRead(
                peripheral: peripheral,
                characteristic: readWrite
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        if let index = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[index].rssi = RSSI.intValue
            devices = devices
        }
    }
}
