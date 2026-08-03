import SwiftUI

struct IOSRootView: View {
    @EnvironmentObject private var bluetooth: BLEManager

    var body: some View {
        NavigationStack {
            DeviceDiscoveryView()
                .navigationDestination(for: UUID.self) { deviceID in
                    IOSDeviceDetailView(deviceID: deviceID)
                }
        }
        .tint(.blue)
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
    }
}

private struct DeviceDiscoveryView: View {
    @EnvironmentObject private var bluetooth: BLEManager
    @State private var showsFilters = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                bluetoothStatusCard

                if bluetooth.visibleDevices.isEmpty {
                    emptyState
                } else {
                    ForEach(bluetooth.visibleDevices) { device in
                        NavigationLink(value: device.id) {
                            IOSDeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("YD 动力调试")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("扫描筛选")

                Button {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.refreshScan()
                } label: {
                    if bluetooth.isScanning {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel(bluetooth.isScanning ? "停止扫描" : "刷新扫描")
            }
        }
        .sheet(isPresented: $showsFilters) {
            ScanFilterSheet()
                .environmentObject(bluetooth)
                .presentationDetents([.medium])
        }
    }

    private var bluetoothStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(bluetooth.isScanning ? "正在查找车辆" : bluetooth.bluetoothState)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bluetooth.bluetoothState == "蓝牙已开启" ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(
                            bluetooth.isScanning
                                ? "扫描将在 5 秒后自动结束"
                                : "找到 \(bluetooth.visibleDevices.count) 个匹配设备"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.refreshScan()
            } label: {
                Label(
                    bluetooth.isScanning ? "停止扫描" : "扫描附近车辆",
                    systemImage: bluetooth.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .iosCard()
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(bluetooth.isScanning ? "正在寻找 YD 设备" : "暂未发现车辆")
                    .font(.title3.weight(.semibold))
                Text("请靠近车辆并确认车辆蓝牙已唤醒。默认只显示名称以 YD 开头且信号达到阈值的设备。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 52)
    }
}

private struct ScanFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: BLEManager

    var body: some View {
        NavigationStack {
            Form {
                Section("设备名称") {
                    TextField("例如 YD", text: $bluetooth.deviceNamePrefix)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    Slider(
                        value: Binding(
                            get: { Double(bluetooth.minimumRSSI) },
                            set: { bluetooth.minimumRSSI = Int($0) }
                        ),
                        in: -100 ... -20,
                        step: 1
                    )
                } header: {
                    HStack {
                        Text("最低信号强度")
                        Spacer()
                        Text("\(bluetooth.minimumRSSI) dBm")
                            .monospacedDigit()
                    }
                } footer: {
                    Text("数值越接近 0，筛选条件越严格。")
                }
            }
            .navigationTitle("扫描筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct IOSDeviceRow: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(device.phase == .ready ? Color.green.opacity(0.13) : Color.blue.opacity(0.1))
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(device.phase == .ready ? .green : .blue)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(device.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    phaseBadge
                    if !device.advertisement.macCandidates.isEmpty {
                        Label(
                            "\(device.advertisement.macCandidates.count) 个 MAC",
                            systemImage: "key.horizontal"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                Image(systemName: signalIcon(device.rssi))
                    .foregroundStyle(.secondary)
                Text("\(device.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .iosCard()
    }

    private var phaseBadge: some View {
        Text(device.phase.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(device.phase == .ready ? .green : device.phase == .failed ? .red : .secondary)
    }
}

private struct IOSDeviceDetailView: View {
    @EnvironmentObject private var bluetooth: BLEManager

    let deviceID: UUID

    @State private var macAddress = ""
    @State private var customHex = ""
    @State private var confirmation: PowerConfirmation?
    @State private var showsLogs = false
    @State private var showsAdvanced = false

    private enum PowerConfirmation: String, Identifiable {
        case unlock
        case restore

        var id: String { rawValue }
    }

    private var device: DiscoveredDevice? {
        bluetooth.devices.first { $0.id == deviceID }
    }

    var body: some View {
        Group {
            if let device {
                ScrollView {
                    VStack(spacing: 14) {
                        deviceHero(device)
                        connectionCard(device)

                        if device.phase == .ready {
                            powerControlCard
                            volumeCard
                        }

                        advancedCard(device)
                        recentLogCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 24)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(device.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsLogs = true
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .accessibilityLabel("通信日志")
                    }
                }
                .sheet(isPresented: $showsLogs) {
                    IOSLogView()
                        .environmentObject(bluetooth)
                }
                .confirmationDialog(
                    confirmation == .unlock ? "确认解除动力锁定？" : "确认恢复动力锁定？",
                    isPresented: Binding(
                        get: { confirmation != nil },
                        set: { if !$0 { confirmation = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    if confirmation == .unlock {
                        Button("解除动力锁定", role: .destructive) {
                            bluetooth.unlockPower()
                            confirmation = nil
                        }
                    } else {
                        Button("恢复动力锁定") {
                            bluetooth.restorePowerLock()
                            confirmation = nil
                        }
                    }
                    Button("取消", role: .cancel) {
                        confirmation = nil
                    }
                } message: {
                    Text("请确认车辆属于你或已获授权，并确保车辆停稳、支架可靠、车轮离地或周围无障碍物。")
                }
                .onAppear {
                    loadSuggestedMAC()
                }
                .onChange(of: device.advertisement.macCandidates.first?.address) { _, _ in
                    loadSuggestedMAC()
                }
            } else {
                ContentUnavailableView(
                    "设备已离开",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("请返回设备列表并重新扫描。")
                )
            }
        }
    }

    private func deviceHero(_ device: DiscoveredDevice) -> some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                Image(systemName: "bicycle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 6) {
                Text(device.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("\(device.rssi) dBm", systemImage: signalIcon(device.rssi))
                    phasePill(device.phase)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .iosCard()
    }

    private func connectionCard(_ device: DiscoveredDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            IOSSectionHeader(
                title: "连接与认证",
                subtitle: "iPhone 不公开硬件地址，优先从车辆广播中识别",
                systemImage: "link"
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("设备 MAC 地址")
                    .font(.subheadline.weight(.semibold))
                TextField("A1:B2:C3:D4:E5:F6", text: $macAddress)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    }
                    .disabled(device.isConnected)
            }

            if device.advertisement.macCandidates.isEmpty {
                Label("广播中未识别到地址，请按车辆标签手动填写。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("发现 \(device.advertisement.macCandidates.count) 个候选")
                        .font(.subheadline.weight(.semibold))

                    ForEach(device.advertisement.macCandidates.prefix(4)) { candidate in
                        Button {
                            macAddress = candidate.address
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: macAddress == candidate.address ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(macAddress == candidate.address ? Color.blue : Color.secondary.opacity(0.45))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.address)
                                        .font(.subheadline.monospaced().weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(candidate.source) · 可信度\(candidate.confidence.title)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(device.isConnected)
                    }
                }
            }

            if device.isConnected || device.phase == .ready {
                Button(role: .destructive) {
                    bluetooth.disconnect()
                } label: {
                    Label("断开连接", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    bluetooth.connect(to: device.id, macAddress: macAddress)
                } label: {
                    Label("连接并认证", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    device.phase == .connecting
                        || device.phase == .disconnecting
                        || macAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .iosCard()
    }

    private var powerControlCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            IOSSectionHeader(
                title: "动力锁定",
                subtitle: "仅操作本人拥有或已获授权的车辆",
                systemImage: "bolt.fill"
            )

            Label(
                "操作前请让车辆完全停稳。指令成功后，动力状态可能立即发生变化。",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                confirmation = .unlock
            } label: {
                Label("解除动力锁定", systemImage: "lock.open.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.orange)

            Button {
                confirmation = .restore
            } label: {
                Label("恢复动力锁定", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .iosCard()
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            IOSSectionHeader(
                title: "提示音音量",
                subtitle: "选择车辆支持的音量参数",
                systemImage: "speaker.wave.2.fill"
            )

            HStack(spacing: 10) {
                ForEach([4, 6, 7], id: \.self) { level in
                    Button("等级 \(level)") {
                        bluetooth.sendVolume(level)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .iosCard()
    }

    private func advancedCard(_ device: DiscoveredDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showsAdvanced) {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()

                    IOSInfoRow(title: "CoreBluetooth ID", value: device.id.uuidString)
                    IOSInfoRow(
                        title: "Manufacturer Data",
                        value: device.advertisement.manufacturerData?.spacedHex ?? "—"
                    )
                    IOSInfoRow(
                        title: "广播服务",
                        value: device.advertisedServices.isEmpty
                            ? "—"
                            : device.advertisedServices.joined(separator: "\n")
                    )

                    if device.phase == .ready {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("自定义 HEX")
                                .font(.subheadline.weight(.semibold))
                            TextField("例如 59 44 39 08 …", text: $customHex, axis: .vertical)
                                .font(.callout.monospaced())
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .lineLimit(2 ... 5)
                                .padding(10)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button("发送 HEX") {
                                bluetooth.sendCustomHex(customHex)
                            }
                            .buttonStyle(.bordered)
                            .disabled(customHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                IOSSectionHeader(
                    title: "高级信息",
                    subtitle: "广播数据与自定义调试帧",
                    systemImage: "terminal"
                )
            }
            .tint(.primary)
        }
        .iosCard()
    }

    private var recentLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IOSSectionHeader(
                    title: "通信日志",
                    subtitle: "最近 \(min(bluetooth.logs.count, 3)) 条",
                    systemImage: "list.bullet.rectangle"
                )
                Spacer()
                Button("全部") {
                    showsLogs = true
                }
                .font(.subheadline)
            }

            if bluetooth.logs.isEmpty {
                Text("连接车辆后，认证与指令收发记录会显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 9) {
                    ForEach(bluetooth.logs.suffix(3)) { entry in
                        IOSCompactLogRow(entry: entry)
                    }
                }
            }
        }
        .iosCard()
    }

    private func loadSuggestedMAC() {
        guard let device else { return }
        if device.isConnected, !macAddress.isEmpty {
            return
        }

        if let highConfidence = bluetooth.preferredMACCandidate(for: device.id) {
            macAddress = highConfidence.address
            return
        }

        let saved = bluetooth.savedMACAddress(for: device.id)
        if !saved.isEmpty {
            macAddress = saved
        }
    }
}

private struct IOSLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bluetooth: BLEManager

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if bluetooth.logs.isEmpty {
                            ContentUnavailableView(
                                "暂无日志",
                                systemImage: "list.bullet.rectangle",
                                description: Text("连接车辆后将在这里显示通信记录。")
                            )
                            .padding(.top, 80)
                        } else {
                            ForEach(bluetooth.logs) { entry in
                                IOSFullLogRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .onChange(of: bluetooth.logs.count) { _, _ in
                    if let id = bluetooth.logs.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("通信日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        bluetooth.clearLogs()
                    }
                    .disabled(bluetooth.logs.isEmpty)
                }
            }
        }
    }
}

private struct IOSCompactLogRow: View {
    let entry: BLELogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(entry.direction.rawValue)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(logColor(entry.direction))
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(entry.direction == .error ? .red : .primary)
                    .lineLimit(2)
                if let data = entry.data {
                    Text(data.spacedHex)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IOSFullLogRow: View {
    let entry: BLELogEntry

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(entry.direction.rawValue)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(logColor(entry.direction))
                Spacer()
                Text(Self.formatter.string(from: entry.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(entry.message)
                .font(.subheadline)
                .foregroundStyle(entry.direction == .error ? .red : .primary)
            if let data = entry.data {
                Text(data.spacedHex)
                    .font(.caption.monospaced())
                    .foregroundStyle(entry.direction == .sent ? .blue : .green)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosCard(padding: 13)
    }
}

private struct IOSSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct IOSInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension View {
    func iosCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
    }
}

private func phasePill(_ phase: DeviceConnectionPhase) -> some View {
    HStack(spacing: 5) {
        Circle()
            .fill(phase == .ready ? Color.green : phase == .failed ? Color.red : Color.orange)
            .frame(width: 6, height: 6)
        Text(phase.title)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.primary.opacity(0.055), in: Capsule())
}

private func signalIcon(_ rssi: Int) -> String {
    if rssi >= -50 { return "wifi" }
    if rssi >= -70 { return "wifi.exclamationmark" }
    return "wifi.slash"
}

private func logColor(_ direction: BLELogDirection) -> Color {
    switch direction {
    case .system: return .secondary
    case .sent: return .blue
    case .received: return .green
    case .error: return .red
    }
}
