import SwiftUI
import WidgetKit

@main
struct Baki_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                WidgetCenter.shared.reloadTimelines(ofKind: "BakiTimetableWidget")
            }
        }
    }
}
