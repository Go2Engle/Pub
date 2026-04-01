import Foundation

actor HomebrewService {
    private let runner: BrewCommandRunner

    init(runner: BrewCommandRunner = BrewCommandRunner()) {
        self.runner = runner
    }

    func brewLocation() async -> String? {
        await runner.brewLocation()
    }

    func loadInstalledPackages() async throws -> [BrewPackage] {
        async let infoResult = runner.run(["info", "--json=v2", "--installed"])
        async let outdatedResult = runner.run(["outdated", "--json=v2"])

        let infoData = Data(try await infoResult.stdout.utf8)
        let outdatedData = Data(try await outdatedResult.stdout.utf8)
        return try HomebrewCatalogDecoder.decodeInstalledPackages(infoData: infoData, outdatedData: outdatedData)
    }

    func searchPackages(matching query: String) async throws -> [BrewPackage] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        let searchResult = try await runner.run(["search", "--formulae", "--casks", trimmedQuery])
        let candidates = HomebrewCatalogDecoder.searchTokens(from: searchResult.stdout)
        guard !candidates.isEmpty else {
            return []
        }

        let limitedCandidates = Array(candidates.prefix(20))
        let infoResult = try await runner.run(["info", "--json=v2"] + limitedCandidates)
        return try HomebrewCatalogDecoder.decodeSearchPackages(infoData: Data(infoResult.stdout.utf8))
    }

    func install(_ package: BrewPackage, stream: @escaping @Sendable (String) -> Void) async throws {
        _ = try await runner.run(["install", package.kind.cliFlag, package.name], stream: stream)
    }

    func uninstall(_ package: BrewPackage, stream: @escaping @Sendable (String) -> Void) async throws {
        _ = try await runner.run(["uninstall", package.kind.cliFlag, package.name], stream: stream)
    }

    func upgrade(_ package: BrewPackage, stream: @escaping @Sendable (String) -> Void) async throws {
        _ = try await runner.run(["upgrade", package.kind.cliFlag, package.name], stream: stream)
    }

    func upgradeAll(stream: @escaping @Sendable (String) -> Void) async throws {
        _ = try await runner.run(["upgrade"], stream: stream)
    }
}

enum HomebrewCatalogDecoder {
    static func decodeInstalledPackages(infoData: Data, outdatedData: Data) throws -> [BrewPackage] {
        let decoder = JSONDecoder()
        let infoEnvelope = try decoder.decode(BrewInfoEnvelope.self, from: infoData)
        let outdatedEnvelope = try decoder.decode(BrewOutdatedEnvelope.self, from: outdatedData)
        let outdatedMap = outdatedEnvelope.outdatedVersionsByID

        let formulae = infoEnvelope.formulae.map { $0.package(outdatedVersion: outdatedMap["formula:\($0.name)"]) }
        let casks = infoEnvelope.casks.map { $0.package(outdatedVersion: outdatedMap["cask:\($0.token)"]) }
        return (formulae + casks).sorted(by: PackageOrdering.standard)
    }

    static func decodeSearchPackages(infoData: Data) throws -> [BrewPackage] {
        let decoder = JSONDecoder()
        let infoEnvelope = try decoder.decode(BrewInfoEnvelope.self, from: infoData)
        let formulae = infoEnvelope.formulae.map { $0.package(outdatedVersion: nil) }
        let casks = infoEnvelope.casks.map { $0.package(outdatedVersion: nil) }
        return (formulae + casks).sorted(by: PackageOrdering.standard)
    }

    static func searchTokens(from output: String) -> [String] {
        var tokens: [String] = []
        var seen = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("==>") else {
                continue
            }

            guard seen.insert(line).inserted else {
                continue
            }
            tokens.append(line)
        }

        return tokens
    }
}

private struct BrewInfoEnvelope: Decodable {
    let formulae: [FormulaInfo]
    let casks: [CaskInfo]
}

private struct BrewOutdatedEnvelope: Decodable {
    let formulae: [OutdatedPackage]
    let casks: [OutdatedPackage]

    var outdatedVersionsByID: [String: String] {
        var result: [String: String] = [:]

        for package in formulae {
            result["formula:\(package.name)"] = package.currentVersion
        }

        for package in casks {
            result["cask:\(package.name)"] = package.currentVersion
        }

        return result
    }
}

private struct OutdatedPackage: Decodable {
    let name: String
    let currentVersion: String

    private enum CodingKeys: String, CodingKey {
        case name
        case currentVersion = "current_version"
    }
}

private struct FormulaInfo: Decodable {
    let name: String
    let desc: String?
    let homepage: String?
    let aliases: [String]
    let installed: [InstalledFormula]
    let linkedKeg: String?
    let pinned: Bool?
    let outdated: Bool?
    let versions: FormulaVersions?
    let tap: String?
    let dependencies: [String]?
    let caveats: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case desc
        case homepage
        case aliases
        case installed
        case linkedKeg = "linked_keg"
        case pinned
        case outdated
        case versions
        case tap
        case dependencies
        case caveats
    }

    func package(outdatedVersion: String?) -> BrewPackage {
        let installedVersion = installed.last?.version ?? linkedKeg
        let latestVersion = outdatedVersion ?? versions?.stable
        let description = desc?.trimmingCharacters(in: .whitespacesAndNewlines)

        return BrewPackage(
            name: name,
            displayName: name,
            description: description?.isEmpty == false ? description! : "No description available.",
            homepage: homepage,
            installedVersion: installedVersion,
            latestVersion: latestVersion,
            kind: .formula,
            tap: tap,
            aliases: aliases,
            dependencies: dependencies ?? [],
            caveats: caveats,
            installed: installedVersion != nil,
            outdated: outdatedVersion != nil || outdated == true,
            pinned: pinned == true,
            installedOnRequest: installed.contains(where: \.installedOnRequest)
        )
    }
}

private struct InstalledFormula: Decodable {
    let version: String
    let installedOnRequest: Bool

    private enum CodingKeys: String, CodingKey {
        case version
        case installedOnRequest = "installed_on_request"
    }
}

private struct FormulaVersions: Decodable {
    let stable: String?
}

private struct CaskInfo: Decodable {
    let token: String
    let name: [String]?
    let desc: String?
    let homepage: String?
    let version: String?
    let installed: InstalledCaskVersion?
    let outdated: Bool?
    let tap: String?
    let caveats: String?

    func package(outdatedVersion: String?) -> BrewPackage {
        let displayName = name?.first ?? token
        let description = desc?.trimmingCharacters(in: .whitespacesAndNewlines)

        return BrewPackage(
            name: token,
            displayName: displayName,
            description: description?.isEmpty == false ? description! : "No description available.",
            homepage: homepage,
            installedVersion: installed?.primaryVersion,
            latestVersion: outdatedVersion ?? version,
            kind: .cask,
            tap: tap,
            aliases: [],
            dependencies: [],
            caveats: caveats,
            installed: installed != nil,
            outdated: outdatedVersion != nil || outdated == true,
            pinned: false,
            installedOnRequest: installed != nil
        )
    }
}

private enum InstalledCaskVersion: Decodable {
    case string(String)
    case array([String])

    var primaryVersion: String? {
        switch self {
        case let .string(value):
            value
        case let .array(values):
            values.first
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        self = .array(try container.decode([String].self))
    }
}
