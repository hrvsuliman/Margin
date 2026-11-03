import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct MarginApp: App {
    @State private var settings = AppSettings.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NavigationBarStyle.apply()
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(\.locale, .margin)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Palette.marginRed)
        }
        .modelContainer(Persistence.container)
    }
}

/// Serif navigation titles (New York), the app's typographic signature.
enum NavigationBarStyle {
    static func apply() {
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: serif(.largeTitle, weight: .bold)]
        appearance.titleTextAttributes = [.font: serif(.headline, weight: .semibold)]
    }

    private static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
