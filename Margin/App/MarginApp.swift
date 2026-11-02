import SwiftUI

@main
struct MarginApp: App {
    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .tint(Palette.marginRed)
        }
    }
}
