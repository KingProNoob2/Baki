import SwiftUI

#if os(iOS)
import UIKit

final class BakiAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationService.shared.configure()
        PushService.shared.registerForPush()
        _ = PhoneLinkManager.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushService.shared.didReceiveDeviceToken(deviceToken)
    }
}
#endif

@main
struct BakiPhoneApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BakiAppDelegate.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            RootView { MacMainView() }
                .formStyle(.grouped)
                .frame(minWidth: 980, minHeight: 620)
            #else
            RootView { MainTabView() }
                .formStyle(.grouped)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        NotificationService.shared.stopForegroundPolling()
                        NotificationService.shared.scheduleBackgroundRefresh()
                    case .inactive:
                        NotificationService.shared.stopForegroundPolling()
                    case .active:
                        NotificationService.shared.startForegroundPolling()
                        Task {
                            await NotificationService.shared.refreshAuthorizationStatus()
                            await NotificationService.shared.checkOnForegroundIfStale()
                        }
                    default:
                        break
                    }
                }
            #endif
        }
        #if os(macOS)
        .commands { BakiCommands() }
        #endif

        #if os(macOS)
        Settings {
            MacSettingsView()
        }
        #endif
    }
}
