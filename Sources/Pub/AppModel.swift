import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: PackageSection = .installed {
        didSet {
            queueSearchIfNeeded()
            syncSelection()
        }
    }
    @Published var selectedPackageID: BrewPackage.ID?
    @Published var searchText = "" {
        didSet {
            queueSearchIfNeeded()
        }
    }
    @Published private(set) var installedPackages: [BrewPackage] = []
    @Published private(set) var searchResults: [BrewPackage] = []
    @Published private(set) var brewLocation = "Locating brew..."
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSearching = false
    @Published private(set) var activeOperation: PackageOperation?
    @Published private(set) var activityLog = ""
    @Published var errorMessage: String?

    private let service: HomebrewService
    private var hasLoaded = false
    private var searchTask: Task<Void, Never>?

    init(service: HomebrewService = HomebrewService()) {
        self.service = service
    }

    var isRunningOperation: Bool {
        activeOperation != nil
    }

    var outdatedPackages: [BrewPackage] {
        installedPackages.filter(\.outdated).sorted(by: PackageOrdering.standard)
    }

    var visiblePackages: [BrewPackage] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch selectedSection {
        case .installed:
            return filter(packages: installedPackages, query: trimmedQuery)
        case .outdated:
            return filter(packages: outdatedPackages, query: trimmedQuery)
        case .discover:
            return searchResults
        }
    }

    var selectedPackage: BrewPackage? {
        visiblePackages.first(where: { $0.id == selectedPackageID })
            ?? installedPackages.first(where: { $0.id == selectedPackageID })
            ?? searchResults.first(where: { $0.id == selectedPackageID })
    }

    func startup() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let brewLocation = await service.brewLocation() {
            self.brewLocation = brewLocation
        } else {
            self.brewLocation = "brew not found"
        }

        await refresh()
    }

    func refreshFromCommand() {
        Task {
            await refresh()
        }
    }

    func upgradeAllFromCommand() {
        guard !outdatedPackages.isEmpty else { return }

        Task {
            await performGlobalAction(.upgradeAll, packageName: nil) {
                try await self.service.upgradeAll(stream: self.makeLogStream())
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            installedPackages = try await service.loadInstalledPackages()
            if let brewLocation = await service.brewLocation() {
                self.brewLocation = brewLocation
            }
            syncSelection()
            queueSearchIfNeeded()
        } catch {
            present(error)
        }
    }

    func perform(_ action: PackageAction, on package: BrewPackage) {
        guard activeOperation == nil else { return }

        Task {
            switch action {
            case .install:
                await performGlobalAction(.install, packageName: package.displayName) {
                    try await self.service.install(package, stream: self.makeLogStream())
                }
                selectedSection = .installed
            case .uninstall:
                await performGlobalAction(.uninstall, packageName: package.displayName) {
                    try await self.service.uninstall(package, stream: self.makeLogStream())
                }
            case .upgrade:
                await performGlobalAction(.upgrade, packageName: package.displayName) {
                    try await self.service.upgrade(package, stream: self.makeLogStream())
                }
            case .upgradeAll:
                await performGlobalAction(.upgradeAll, packageName: nil) {
                    try await self.service.upgradeAll(stream: self.makeLogStream())
                }
            }
        }
    }

    func clearLog() {
        activityLog = ""
    }

    private func performGlobalAction(
        _ action: PackageAction,
        packageName: String?,
        work: @escaping () async throws -> Void
    ) async {
        guard activeOperation == nil else { return }

        activityLog = ""
        activeOperation = PackageOperation(title: action.title, packageName: packageName)
        appendLog("$ \(action.title.lowercased()) \(packageName ?? "packages")\n\n")

        do {
            try await work()
            appendLog("\nCompleted successfully.\n")
            await refresh()
        } catch {
            appendLog("\nFailed: \(error.localizedDescription)\n")
            present(error)
        }

        activeOperation = nil
    }

    private func makeLogStream() -> @Sendable (String) -> Void {
        { [weak self] chunk in
            Task { @MainActor [weak self] in
                self?.appendLog(chunk)
            }
        }
    }

    private func appendLog(_ chunk: String) {
        activityLog.append(chunk)
    }

    private func filter(packages: [BrewPackage], query: String) -> [BrewPackage] {
        guard !query.isEmpty else { return packages }
        return packages.filter { $0.searchableText.contains(query) }
    }

    private func queueSearchIfNeeded() {
        searchTask?.cancel()

        guard selectedSection == .discover else {
            isSearching = false
            return
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            syncSelection()
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let results = try await service.searchPackages(matching: query)

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                    self.syncSelection()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isSearching = false
                    self.present(error)
                }
            }
        }
    }

    private func syncSelection() {
        if let selectedPackageID, visiblePackages.contains(where: { $0.id == selectedPackageID }) {
            return
        }
        selectedPackageID = visiblePackages.first?.id
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
