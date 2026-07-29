import SwiftUI

@main
struct YDEbikeHelperApp: App {
    @StateObject private var bluetooth = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bluetooth)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(bluetooth.isScanning ? "停止扫描" : "刷新扫描") {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.refreshScan()
                }
                .keyboardShortcut("r")
            }
        }
    }
}
