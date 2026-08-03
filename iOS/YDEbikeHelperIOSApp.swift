import SwiftUI

@main
struct YDEbikeHelperIOSApp: App {
    @StateObject private var bluetooth = BLEManager()

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(bluetooth)
        }
    }
}
