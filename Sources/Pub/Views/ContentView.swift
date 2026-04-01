import AppKit
import SwiftUI

private enum ToolbarItemID {
    static let refresh = "pub.refresh"
    static let upgradeAll = "pub.upgradeAll"
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            detail
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: searchPlaceholder)
        .background(WindowConfigurator())
        .frame(minWidth: 900, minHeight: 620)
        .task {
            await model.startup()
        }
        .alert("Pub", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(model.visiblePackages, selection: $model.selectedPackageID) { package in
                PackageRowView(package: package)
                    .tag(package.id)
            }
            .overlay {
                if model.visiblePackages.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySystemImage,
                        description: Text(emptyDescription)
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(id: ToolbarItemID.refresh, placement: .automatic) {
                Button {
                    model.refreshFromCommand()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh the installed package list and Homebrew status.")
                .disabled(model.isRefreshing || model.isRunningOperation)
            }

            ToolbarItem(id: ToolbarItemID.upgradeAll, placement: .automatic) {
                Button {
                    model.upgradeAllFromCommand()
                } label: {
                    Label("Upgrade All", systemImage: "arrow.up.circle")
                }
                .help("Upgrade every outdated Homebrew package.")
                .disabled(model.isRefreshing || model.isRunningOperation || model.outdatedPackages.isEmpty)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "mug.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pub")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Homebrew Package Manager")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                StatCard(title: "Installed", value: "\(model.installedPackages.count)", tint: .blue, icon: "shippingbox.fill")
                StatCard(title: "Outdated", value: "\(model.outdatedPackages.count)", tint: .orange, icon: "exclamationmark.arrow.circlepath")
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Section", selection: $model.selectedSection) {
                    ForEach(PackageSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    Image(systemName: model.brewLocation == "brew not found" ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(model.brewLocation == "brew not found" ? .red : .green)

                    Text(model.brewLocation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if model.isRefreshing || model.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let package = model.selectedPackage {
            PackageDetailView(
                package: package,
                isBusy: model.isRunningOperation,
                operation: model.activeOperation,
                activityLog: model.activityLog,
                onAction: { action in
                    model.perform(action, on: package)
                },
                onClearLog: model.clearLog
            )
        } else {
            ContentUnavailableView(
                "Select a Package",
                systemImage: "shippingbox",
                description: Text("Choose a package from the sidebar to inspect versions, open its homepage, or manage it with Homebrew.")
            )
        }
    }

    private var searchPlaceholder: String {
        switch model.selectedSection {
        case .discover:
            "Search Homebrew formulas and casks"
        case .installed:
            "Filter installed packages"
        case .outdated:
            "Filter outdated packages"
        }
    }

    private var emptyTitle: String {
        switch model.selectedSection {
        case .installed:
            "No Packages"
        case .outdated:
            "Everything is Up to Date"
        case .discover:
            model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Search Homebrew" : "No Matches"
        }
    }

    private var emptyDescription: String {
        switch model.selectedSection {
        case .installed:
            "Install packages with Homebrew and they will appear here."
        case .outdated:
            "Pub did not find any installed packages with newer versions available."
        case .discover:
            model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Type a name or keyword to search the Homebrew catalog."
                : "Try a different package name or a broader query."
        }
    }

    private var emptySystemImage: String {
        switch model.selectedSection {
        case .installed:
            "tray"
        case .outdated:
            "checkmark.circle"
        case .discover:
            "magnifyingglass"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            }
        )
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView)
        }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.minSize = NSSize(width: 900, height: 620)
        window.styleMask.insert(.resizable)
        configureToolbarItems(for: window)
    }

    private func configureToolbarItems(for window: NSWindow) {
        guard let toolbar = window.toolbar else { return }

        for item in toolbar.items {
            switch item.itemIdentifier.rawValue {
            case ToolbarItemID.refresh:
                item.toolTip = "Refresh the installed package list and Homebrew status."
            case ToolbarItemID.upgradeAll:
                item.toolTip = "Upgrade every outdated Homebrew package."
            default:
                continue
            }
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct PackageRowView: View {
    let package: BrewPackage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: package.kind == .formula ? "hammer.fill" : "macwindow")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(package.kind == .formula ? .blue : .mint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((package.kind == .formula ? Color.blue : Color.mint).opacity(0.1))
                )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(package.displayName)
                        .font(.headline)

                    if package.outdated {
                        Badge(text: "Update", tint: .orange, icon: "arrow.up.circle.fill")
                    } else if package.installed {
                        Badge(text: "Installed", tint: .green, icon: "checkmark.circle.fill")
                    }
                }

                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(package.versionLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PackageDetailView: View {
    let package: BrewPackage
    let isBusy: Bool
    let operation: PackageOperation?
    let activityLog: String
    let onAction: (PackageAction) -> Void
    let onClearLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    metadata
                    if let caveats = package.caveats, !caveats.isEmpty {
                        GroupBox {
                            Text(caveats)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Caveats", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            logArea
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.25))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: package.kind == .formula ? "hammer.fill" : "macwindow")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(package.kind == .formula ? .blue : .mint)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill((package.kind == .formula ? Color.blue : Color.mint).opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder((package.kind == .formula ? Color.blue : Color.mint).opacity(0.15), lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(package.displayName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    HStack(spacing: 8) {
                        Badge(text: package.kind.label, tint: package.kind == .formula ? .blue : .mint, icon: package.kind == .formula ? "hammer" : "macwindow")
                        if package.outdated {
                            Badge(text: "Upgrade available", tint: .orange, icon: "arrow.up.circle.fill")
                        } else if package.installed {
                            Badge(text: "Installed", tint: .green, icon: "checkmark.circle.fill")
                        }
                        if package.pinned {
                            Badge(text: "Pinned", tint: .gray, icon: "pin.fill")
                        }
                    }

                    Text(package.description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    actionButtons
                    if let operation {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("\(operation.title) in progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var metadata: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                MetadataRow(icon: "tag", label: "Name", value: package.name)
                Divider().padding(.leading, 32)
                MetadataRow(icon: "circle.fill", label: "Status", value: package.statusSummary,
                            tint: package.outdated ? .orange : (package.installed ? .green : .secondary))
                Divider().padding(.leading, 32)
                MetadataRow(icon: "number", label: "Version", value: package.versionLine)
                if let tap = package.tap {
                    Divider().padding(.leading, 32)
                    MetadataRow(icon: "spigot", label: "Tap", value: tap)
                }
                if !package.aliases.isEmpty {
                    Divider().padding(.leading, 32)
                    MetadataRow(icon: "textformat.abc", label: "Aliases", value: package.aliases.joined(separator: ", "))
                }
                if !package.dependencies.isEmpty {
                    Divider().padding(.leading, 32)
                    MetadataRow(icon: "link", label: "Dependencies", value: package.dependencies.joined(separator: ", "))
                }
                if let homepage = package.homepage, let url = URL(string: homepage) {
                    Divider().padding(.leading, 32)
                    Link(destination: url) {
                        HStack(spacing: 10) {
                            Image(systemName: "safari")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                                .frame(width: 22)
                            Text("Open Homepage")
                                .font(.body)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Details", systemImage: "info.circle")
        }
    }

    private var logArea: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Activity", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        onClearLog()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(activityLog.isEmpty || isBusy)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(activityLog.isEmpty ? "Run an install, uninstall, or upgrade command to see Homebrew output here." : activityLog)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(activityLog.isEmpty ? .secondary : Color(nsColor: .textColor))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Color.clear
                            .frame(height: 1)
                            .id("logBottom")
                    }
                    .onChange(of: activityLog) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                    }
                }
                .frame(minHeight: 220)
                .frame(maxHeight: 260)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            if !package.installed {
                Button {
                    onAction(.install)
                } label: {
                    Label("Install", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }

            if package.installed {
                Button(role: .destructive) {
                    onAction(.uninstall)
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }

            if package.outdated {
                Button {
                    onAction(.upgrade)
                } label: {
                    Label("Upgrade", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let tint: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .foregroundStyle(tint)
    }
}

private struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
    }
}
