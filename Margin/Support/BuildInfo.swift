import Foundation

/// Version details read from the app's Info.plist.
/// The build number is the GitHub Actions run number, so you can match
/// the app on your iPhone to the exact build on GitHub.
struct BuildInfo: Equatable {
    static let missing = "–"

    let version: String
    let build: String
    let bundleID: String

    init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String ?? Self.missing
        build = infoDictionary?["CFBundleVersion"] as? String ?? Self.missing
        bundleID = infoDictionary?["CFBundleIdentifier"] as? String ?? Self.missing
    }

    static let current = BuildInfo(infoDictionary: Bundle.main.infoDictionary)

    /// For example "0.1.0 (build 12)".
    var displayVersion: String {
        "\(version) (build \(build))"
    }
}
