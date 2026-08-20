import Foundation

#if os(iOS)
import UIKit
#endif

nonisolated enum AppleBrowserUserAgentProfile: String, Sendable {
    case desktopSafari = "desktop_safari"
    case mobileSafari = "mobile_safari"
}

nonisolated enum AppleBrowserUserAgentPlatform: Sendable {
    case macOS
    case iPhone
    case iPad
}

/// Supplies the Safari identity that the embedded WebKit base user agent omits.
/// The WebKit/Safari build tokens are intentionally frozen by Apple; only the
/// public Safari `Version` component should follow the installed platform.
nonisolated enum AppleBrowserUserAgent {
    private static let macWebKitVersion = "605.1.15"
    private static let mobileSafariVersion = "604.1"

    @MainActor
    static var currentDefault: String {
        current(profile: defaultProfile(for: currentPlatform))
    }

    @MainActor
    static func current(profile: AppleBrowserUserAgentProfile) -> String {
        safari(
            profile: profile,
            platform: currentPlatform,
            version: currentSafariVersion
        )
    }

    static func safari(
        profile: AppleBrowserUserAgentProfile,
        platform: AppleBrowserUserAgentPlatform,
        version: String
    ) -> String {
        let normalizedVersion = normalizedVersion(version) ?? "26.0"
        switch profile {
        case .desktopSafari:
            switch platform {
            case .macOS:
                return joined([
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
                    "AppleWebKit/\(macWebKitVersion)",
                    "(KHTML, like Gecko)",
                    "Version/\(normalizedVersion)",
                    "Safari/\(macWebKitVersion)",
                ])
            case .iPhone, .iPad:
                return joined([
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)",
                    "AppleWebKit/\(macWebKitVersion)",
                    "(KHTML, like Gecko)",
                    "Version/\(normalizedVersion)",
                    "Mobile/15E148",
                    "Safari/\(mobileSafariVersion)",
                ])
            }
        case .mobileSafari:
            let operatingSystemVersion = normalizedVersion.replacing(".", with: "_")
            return joined([
                "Mozilla/5.0 (iPhone; CPU iPhone OS \(operatingSystemVersion) like Mac OS X)",
                "AppleWebKit/\(macWebKitVersion)",
                "(KHTML, like Gecko)",
                "Version/\(normalizedVersion)",
                "Mobile/15E148",
                "Safari/\(mobileSafariVersion)",
            ])
        }
    }

    static func defaultProfile(
        for platform: AppleBrowserUserAgentPlatform
    ) -> AppleBrowserUserAgentProfile {
        switch platform {
        case .macOS, .iPad:
            .desktopSafari
        case .iPhone:
            .mobileSafari
        }
    }

    static func normalizedVersion(_ rawValue: String) -> String? {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = components.first.flatMap({ Int($0) }), major > 0 else {
            return nil
        }
        let minor = components.count > 1 ? Int(components[1]) : 0
        guard let minor, minor >= 0 else { return nil }
        return "\(major).\(minor)"
    }

    private static func joined(_ components: [String]) -> String {
        components.joined(separator: " ")
    }

    @MainActor
    private static var currentPlatform: AppleBrowserUserAgentPlatform {
#if os(macOS)
        .macOS
#elseif os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
#endif
    }

    @MainActor
    private static var currentSafariVersion: String {
#if os(macOS)
        if let installedVersion = installedMacSafariVersion {
            return installedVersion
        }
#endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

#if os(macOS)
    private static var installedMacSafariVersion: String? {
        let applicationPaths = [
            "/Applications/Safari.app",
            "/System/Applications/Safari.app",
        ]
        for path in applicationPaths {
            guard let bundle = Bundle(path: path),
                  let version = bundle.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                  ) as? String,
                  let normalized = normalizedVersion(version) else {
                continue
            }
            return normalized
        }
        return nil
    }
#endif
}
