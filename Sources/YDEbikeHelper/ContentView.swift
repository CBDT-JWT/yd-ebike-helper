import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var bluetooth: BLEManager
    @State private var selectedDeviceID: UUID?
    @State private var macAddress = ""
    @State private var customHex = ""
    @State private var pendingConfirmation: PendingConfirmation?

    private enum PendingConfirmation: String, Identifiable {
        case debug
        case restore

        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 330, max: 420)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                if let device = selectedDevice {
                    deviceDetail(device)
                } else {
                    emptyDetail
                }
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { bluetooth.lastError != nil },
                set: { if !$0 { bluetooth.lastError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {
                bluetooth.lastError = nil
            }
        } message: {
            Text(bluetooth.lastError ?? "")
        }
        .confirmationDialog(
            pendingConfirmation == .debug ? "确认解除动力锁定？" : "确认恢复动力锁定？",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingConfirmation == .debug ? "解除动力锁定" : "恢复动力锁定") {
                if pendingConfirmation == .debug {
                    bluetooth.sendDebugCommand()
                } else {
                    bluetooth.sendRestoreCommand()
                }
                pendingConfirmation = nil
            }
            Button("取消", role: .cancel) {
                pendingConfirmation = nil
            }
        } message: {
            Text("请确认车辆属于你或已获授权，并确保车辆完全停稳后再操作。")
        }
        .onChange(of: selectedDeviceID) { id in
            guard let id else {
                macAddress = ""
                return
            }
            let saved = bluetooth.savedMACAddress(for: id)
            if let systemAddress = bluetooth.systemMACAddress(for: id) {
                macAddress = systemAddress
            } else if let highConfidence = bluetooth.preferredMACCandidate(for: id) {
                macAddress = highConfidence.address
            } else {
                macAddress = saved
            }
        }
    }

    private var selectedDevice: DiscoveredDevice? {
        guard let selectedDeviceID else { return nil }
        return bluetooth.devices.first { $0.id == selectedDeviceID }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("YD E-Bike Helper", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .opacity(bluetooth.isScanning ? 1 : 0)
                }

                HStack(spacing: 8) {
                    statusDot
                    Text(bluetooth.isScanning ? "正在扫描" : bluetooth.bluetoothState)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.refreshScan()
                    } label: {
                        Label(bluetooth.isScanning ? "停止" : "刷新", systemImage: bluetooth.isScanning ? "stop.fill" : "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    TextField("设备名前缀", text: $bluetooth.deviceNamePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 116)
                    Slider(
                        value: Binding(
                            get: { Double(bluetooth.minimumRSSI) },
                            set: { bluetooth.minimumRSSI = Int($0) }
                        ),
                        in: -100 ... -20,
                        step: 1
                    )
                    Text("\(bluetooth.minimumRSSI) dBm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .trailing)
                }
            }
            .padding(18)

            Divider()

            if bluetooth.visibleDevices.isEmpty {
                EmptyStateView(
                    title: bluetooth.isScanning ? "正在寻找设备" : "未发现匹配设备",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: "默认只显示名称以 YD 开头且信号达到阈值的 BLE 设备。"
                )
            } else {
                List(bluetooth.visibleDevices, selection: $selectedDeviceID) { device in
                    DeviceRow(device: device)
                        .tag(device.id)
                }
                .listStyle(.sidebar)
            }
        }
        .background(.thinMaterial)
    }

    private var statusDot: some View {
        Circle()
            .fill(bluetooth.bluetoothState == "蓝牙已开启" ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
            .shadow(
                color: bluetooth.bluetoothState == "蓝牙已开启" ? .green.opacity(0.45) : .clear,
                radius: 4
            )
    }

    private func deviceDetail(_ device: DiscoveredDevice) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    deviceHeader(device)
                    connectionCard(device)
                    advertisementCard(device)
                    if device.phase == .ready {
                        commandCard
                        customConsoleCard
                    }
                    protocolCard
                }
                .padding(26)
            }

            Divider()
            logPanel
                .frame(minHeight: 190, idealHeight: 230, maxHeight: 300)
        }
    }

    private func deviceHeader(_ device: DiscoveredDevice) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: 12) {
                    Label("\(device.rssi) dBm", systemImage: signalIcon(device.rssi))
                    Text(device.id.uuidString)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            Spacer()
            phaseBadge(device.phase)
        }
    }

    private func connectionCard(_ device: DiscoveredDevice) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("设备 MAC 地址")
                            .font(.subheadline.weight(.medium))
                        TextField("A1:B2:C3:D4:E5:F6", text: $macAddress)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .frame(maxWidth: 280)
                            .disabled(device.isConnected)
                        Text("设备名中的明确地址会自动填入；广播二进制中的候选请结合设备标签核对。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !device.advertisement.macCandidates.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("发现 \(device.advertisement.macCandidates.count) 个 MAC 候选")
                                    .font(.caption.weight(.semibold))
                                ForEach(device.advertisement.macCandidates) { candidate in
                                    HStack(spacing: 8) {
                                        Text(candidate.address)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                        confidenceBadge(candidate.confidence)
                                        Text(candidate.source)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Button("使用") {
                                            macAddress = candidate.address
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(device.isConnected)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        } else {
                            Text("当前广播中没有可识别的 MAC 候选。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if device.isConnected || device.phase == .ready {
                        Button("断开连接", role: .destructive) {
                            bluetooth.disconnect()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            bluetooth.connect(to: device.id, macAddress: macAddress)
                        } label: {
                            Label("连接并认证", systemImage: "link")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(device.phase == .connecting || device.phase == .disconnecting)
                    }
                }
            }
            .padding(8)
        } label: {
            Label("连接", systemImage: "cable.connector")
        }
    }

    private func advertisementCard(_ device: DiscoveredDevice) -> some View {
        let advertisement = device.advertisement
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                advertisementRow("CoreBluetooth ID", device.id.uuidString)
                advertisementRow(
                    "系统 BDAddress（私有接口）",
                    advertisement.systemAddress ?? "当前未提供"
                )
                advertisementRow("本地名称", advertisement.localName ?? "—")
                advertisementRow(
                    "可连接",
                    advertisement.isConnectable.map { $0 ? "是" : "否" } ?? "未知"
                )
                advertisementRow(
                    "TX Power",
                    advertisement.txPower.map { "\($0) dBm" } ?? "—"
                )
                advertisementRow(
                    "广播服务",
                    device.advertisedServices.isEmpty
                        ? "—"
                        : device.advertisedServices.joined(separator: ", ")
                )
                advertisementRow(
                    "Solicited 服务",
                    advertisement.solicitedServices.isEmpty
                        ? "—"
                        : advertisement.solicitedServices.joined(separator: ", ")
                )
                advertisementRow(
                    "Overflow 服务",
                    advertisement.overflowServices.isEmpty
                        ? "—"
                        : advertisement.overflowServices.joined(separator: ", ")
                )
                advertisementDataRow(
                    "Manufacturer Data",
                    advertisement.manufacturerData
                )
                if advertisement.serviceData.isEmpty {
                    advertisementRow("Service Data", "—")
                } else {
                    ForEach(advertisement.serviceData.keys.sorted(), id: \.self) { uuid in
                        advertisementDataRow(
                            "Service Data \(uuid)",
                            advertisement.serviceData[uuid]
                        )
                    }
                }
                Text("广播里的 6 字节片段只是候选；正序与逆序都可能出现，最终应以设备标签或厂商信息为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        } label: {
            Label("原始广播数据", systemImage: "wave.3.right")
        }
    }

    private func advertisementRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func advertisementDataRow(_ title: String, _ data: Data?) -> some View {
        advertisementRow(title, data?.spacedHex ?? "—")
    }

    private func confidenceBadge(_ confidence: MACCandidateConfidence) -> some View {
        Text("可信度 \(confidence.title)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(
                confidence == .high ? Color.green
                    : confidence == .medium ? Color.orange
                    : Color.secondary
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private var commandCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        pendingConfirmation = .debug
                    } label: {
                        Label("解除动力锁定", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        pendingConfirmation = .restore
                    } label: {
                        Label("恢复动力锁定", systemImage: "lock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                HStack {
                    Text("音量参数")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach([4, 6, 7], id: \.self) { level in
                        Button("\(level)") {
                            bluetooth.sendVolume(level)
                        }
                        .buttonStyle(.bordered)
                        .frame(width: 60)
                    }
                }
            }
            .padding(8)
        } label: {
            Label("动力锁定与车辆设置", systemImage: "switch.2")
        }
    }

    private var customConsoleCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                TextField("例如 59 44 39 08 …", text: $customHex, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .lineLimit(2 ... 5)
                Button("发送 HEX") {
                    bluetooth.sendCustomHex(customHex)
                }
                .buttonStyle(.bordered)
                .disabled(customHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
        } label: {
            Label("自定义调试帧", systemImage: "terminal")
        }
    }

    private var protocolCard: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                protocolRow("认证服务", YDEbikeProtocol.authenticationService)
                protocolRow("认证读写", YDEbikeProtocol.authenticationReadWriteCharacteristic)
                protocolRow("指令服务", YDEbikeProtocol.commandService)
                protocolRow("指令写入", YDEbikeProtocol.commandWriteCharacteristic)
                protocolRow("指令通知", YDEbikeProtocol.commandNotifyCharacteristic)
            }
            .padding(8)
            .font(.caption)
            .textSelection(.enabled)
        } label: {
            Label("YD GATT 协议", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    private func protocolRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
    }

    private var logPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("通信日志", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                Text("\(bluetooth.logs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") {
                    bluetooth.clearLogs()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(bluetooth.logs) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: bluetooth.logs.count) { _ in
                    if let id = bluetooth.logs.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var emptyDetail: some View {
        EmptyStateView(
            title: "选择一个 BLE 设备",
            systemImage: "antenna.radiowaves.left.and.right",
            description: "从左侧选择 YD 设备以连接、认证并管理动力锁定。"
        )
    }

    private func phaseBadge(_ phase: DeviceConnectionPhase) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phase == .ready ? Color.green : phase == .failed ? Color.red : Color.orange)
                .frame(width: 7, height: 7)
            Text(phase.title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private func signalIcon(_ rssi: Int) -> String {
        if rssi >= -50 { return "wifi" }
        if rssi >= -70 { return "wifi.exclamationmark" }
        return "wifi.slash"
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct DeviceRow: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.title3)
                .foregroundStyle(device.phase == .ready ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(device.phase.title)
                    .font(.caption)
                    .foregroundStyle(device.phase == .failed ? .red : .secondary)
                if !device.advertisement.macCandidates.isEmpty {
                    Label(
                        "\(device.advertisement.macCandidates.count) 个 MAC 候选",
                        systemImage: "key.horizontal"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text("\(device.rssi)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("dBm")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}

private struct LogRow: View {
    let entry: BLELogEntry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .foregroundStyle(.tertiary)
            Text(entry.direction.rawValue)
                .foregroundStyle(directionColor)
                .frame(width: 28, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(entry.direction == .error ? Color.red : Color.primary)
            if let data = entry.data {
                Text(data.spacedHex)
                    .foregroundStyle(entry.direction == .sent ? Color.blue : Color.green)
                    .textSelection(.enabled)
            }
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var directionColor: Color {
        switch entry.direction {
        case .system: return .secondary
        case .sent: return .blue
        case .received: return .green
        case .error: return .red
        }
    }
}
