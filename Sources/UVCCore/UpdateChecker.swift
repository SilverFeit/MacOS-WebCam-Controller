import Foundation
import Combine

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int = 0, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public init?(parsing raw: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return nil }

        // Strip build metadata (+...)
        if let plusIdx = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIdx])
        }

        var pre: String? = nil
        if let dashIdx = cleaned.firstIndex(of: "-") {
            let suffix = String(cleaned[cleaned.index(after: dashIdx)...])
            if !suffix.isEmpty { pre = suffix }
            cleaned = String(cleaned[..<dashIdx])
        }

        let parts = cleaned.split(separator: ".").map(String.init)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        guard let maj = Int(parts[0]) else { return nil }
        let minVal: Int
        if parts.count >= 2 {
            guard let parsedMin = Int(parts[1]) else { return nil }
            minVal = parsedMin
        } else {
            minVal = 0
        }
        let patVal: Int
        if parts.count >= 3 {
            guard let parsedPat = Int(parts[2]) else { return nil }
            patVal = parsedPat
        } else {
            patVal = 0
        }

        self.major = maj
        self.minor = minVal
        self.patch = patVal
        self.prerelease = pre
    }

    public var description: String {
        if let pre = prerelease, !pre.isEmpty {
            return "\(major).\(minor).\(patch)-\(pre)"
        }
        return "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            // Prerelease is lower precedence than normal release (1.1.0-beta < 1.1.0)
            return true
        case (nil, .some):
            return false
        case let (.some(l), .some(r)):
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }
}

public enum AppBuildInfo {
    public static let fallbackVersion = "1.1.0"
    public static let bundleIdentifier = "com.webcamcontroller.uvc"
    public static let githubOwner = "SilverFeit"
    public static let githubRepo = "MacOS-WebCam-Controller"

    public static let repositoryURL = URL(string: "https://github.com/SilverFeit/MacOS-WebCam-Controller")!
    public static let releasesPageURL = URL(string: "https://github.com/SilverFeit/MacOS-WebCam-Controller/releases")!
    public static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/SilverFeit/MacOS-WebCam-Controller/releases/latest")!

    public static let homebrewInstallCommand = "brew install --cask SilverFeit/tap/macos-webcam-controller"
    public static let homebrewUpgradeCommand = "brew upgrade --cask macos-webcam-controller"

    /// Resolves the app bundle version even when invoked through a Homebrew symlink (`/opt/homebrew/bin/webcamctl`).
    public static var currentVersion: String {
        if let direct = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return direct
        }
        let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        if !execPath.isEmpty {
            let resolved = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()
            // .../WebCam Controller.app/Contents/MacOS/webcamctl
            let appURL = resolved
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if appURL.pathExtension == "app",
               let appBundle = Bundle(url: appURL),
               let bundledVer = appBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               !bundledVer.isEmpty {
                return bundledVer
            }
        }
        return fallbackVersion
    }

    public static var currentSemanticVersion: SemanticVersion {
        SemanticVersion(parsing: currentVersion) ?? SemanticVersion(major: 1, minor: 1, patch: 0)
    }
}

public struct GitHubReleaseInfo: Equatable, Sendable, Codable {
    public let tagName: String
    public let versionString: String
    public let title: String
    public let htmlURL: URL
    public let publishedAt: String?

    public init(tagName: String, versionString: String, title: String, htmlURL: URL, publishedAt: String? = nil) {
        self.tagName = tagName
        self.versionString = versionString
        self.title = title
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
    }

    public var semanticVersion: SemanticVersion? {
        SemanticVersion(parsing: tagName) ?? SemanticVersion(parsing: versionString)
    }
}

@MainActor
public final class UpdateChecker: ObservableObject {
    @Published public private(set) var currentVersion: String
    @Published public private(set) var latestRelease: GitHubReleaseInfo?
    @Published public private(set) var isUpdateAvailable: Bool = false
    @Published public private(set) var isChecking: Bool = false
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var statusSummary: String = ""

    private static let minimumAutoRecheckInterval: TimeInterval = 3600 * 6 // 6 hours

    public init(currentVersion: String = AppBuildInfo.currentVersion) {
        self.currentVersion = currentVersion
        self.statusSummary = "v\(currentVersion)"
    }

    public var targetGitHubURL: URL {
        if isUpdateAvailable, let release = latestRelease {
            return release.htmlURL
        }
        return AppBuildInfo.repositoryURL
    }

    public var releasesRedirectURL: URL {
        if let release = latestRelease {
            return release.htmlURL
        }
        return AppBuildInfo.releasesPageURL
    }

    public func checkForUpdates(force: Bool = false) async {
        if isChecking { return }
        if !force, let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.minimumAutoRecheckInterval {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let info = try await Self.fetchLatestGitHubRelease()
            lastCheckedAt = Date()
            latestRelease = info

            let localSem = SemanticVersion(parsing: currentVersion) ?? AppBuildInfo.currentSemanticVersion
            if let remoteSem = info.semanticVersion, remoteSem > localSem {
                isUpdateAvailable = true
                statusSummary = "Update available: v\(remoteSem.description)"
            } else {
                isUpdateAvailable = false
                statusSummary = "Up to date (v\(currentVersion))"
            }
        } catch {
            statusSummary = "v\(currentVersion) (offline)"
        }
    }

    public nonisolated static func fetchLatestGitHubRelease() async throws -> GitHubReleaseInfo {
        var request = URLRequest(url: AppBuildInfo.latestReleaseAPIURL)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacOS-WebCam-Controller/\(AppBuildInfo.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        struct Payload: Decodable {
            let tag_name: String
            let name: String?
            let html_url: String
            let published_at: String?
        }

        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        let url = URL(string: decoded.html_url) ?? AppBuildInfo.releasesPageURL
        let cleanVer = SemanticVersion(parsing: decoded.tag_name)?.description
            ?? decoded.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return GitHubReleaseInfo(
            tagName: decoded.tag_name,
            versionString: cleanVer,
            title: decoded.name ?? decoded.tag_name,
            htmlURL: url,
            publishedAt: decoded.published_at
        )
    }
}
