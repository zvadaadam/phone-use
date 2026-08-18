import Foundation

public enum PhoneUseProtocolMetadata {
    public static let displayName = "Phone Use"
    public static let commandName = "phone-use"
    public static let productIdentifier = "phone-use"
    public static let applicationSupportDirectoryName = "Phone Use"
    public static let currentVersion = 4
    public static let appBundleIdentifier = "com.adamzvada.phoneuse"

    public static func enclosingApplication(for executableURL: URL) -> URL? {
        var candidate = executableURL.resolvingSymlinksInPath().standardizedFileURL
        if !candidate.hasDirectoryPath {
            candidate.deleteLastPathComponent()
        }

        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        return nil
    }

    public static func shortVersion(in bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development"
    }

    public static func shortVersion(of applicationURL: URL) -> String? {
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
            let rawInfo = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let info = rawInfo as? [String: Any],
            let version = info["CFBundleShortVersionString"] as? String,
            !version.isEmpty
        else {
            return nil
        }
        return version
    }

    public static func tokenFile(in applicationSupportURL: URL) -> URL {
        applicationSupportURL
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("token", isDirectory: false)
    }
}
