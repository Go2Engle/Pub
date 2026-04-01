import Foundation

enum BrewPackageKind: String, CaseIterable, Codable, Hashable, Sendable {
    case formula
    case cask

    var label: String {
        switch self {
        case .formula:
            "Formula"
        case .cask:
            "Cask"
        }
    }

    var cliFlag: String {
        switch self {
        case .formula:
            "--formula"
        case .cask:
            "--cask"
        }
    }
}

struct BrewPackage: Identifiable, Hashable, Sendable {
    let name: String
    let displayName: String
    let description: String
    let homepage: String?
    let installedVersion: String?
    let latestVersion: String?
    let kind: BrewPackageKind
    let tap: String?
    let aliases: [String]
    let dependencies: [String]
    let caveats: String?
    let installed: Bool
    let outdated: Bool
    let pinned: Bool
    let installedOnRequest: Bool

    var id: String {
        "\(kind.rawValue):\(name)"
    }

    var versionLine: String {
        switch (installedVersion, latestVersion, outdated) {
        case let (installed?, latest?, true):
            "\(installed) -> \(latest)"
        case let (installed?, _, _):
            installed
        case let (_, latest?, _):
            latest
        default:
            "Unknown"
        }
    }

    var statusSummary: String {
        if outdated {
            return "Upgrade available"
        }
        if installed {
            return "Installed"
        }
        return "Not installed"
    }

    var searchableText: String {
        ([name, displayName, description] + aliases).joined(separator: " ").lowercased()
    }
}

enum PackageOrdering {
    static func standard(_ lhs: BrewPackage, _ rhs: BrewPackage) -> Bool {
        if lhs.outdated != rhs.outdated {
            return lhs.outdated && !rhs.outdated
        }
        if lhs.installed != rhs.installed {
            return lhs.installed && !rhs.installed
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

enum PackageSection: String, CaseIterable, Identifiable {
    case installed
    case outdated
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed:
            "Installed"
        case .outdated:
            "Outdated"
        case .discover:
            "Discover"
        }
    }

    var subtitle: String {
        switch self {
        case .installed:
            "Everything on this machine"
        case .outdated:
            "Ready to upgrade"
        case .discover:
            "Search Homebrew remotely"
        }
    }
}

enum PackageAction: Hashable {
    case install
    case uninstall
    case upgrade
    case upgradeAll

    var title: String {
        switch self {
        case .install:
            "Install"
        case .uninstall:
            "Uninstall"
        case .upgrade:
            "Upgrade"
        case .upgradeAll:
            "Upgrade All"
        }
    }
}

struct PackageOperation: Equatable {
    let title: String
    let packageName: String?
}
