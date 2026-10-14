import AppKit
import SwiftUI

/// The Launchpad: a big matte card hanging from the notch with a search field, the app grid and page dots.
/// Click an empty spot, press Esc (twice while searching) or the shortcut again to close.
struct LaunchpadView: View {
    var island: Island
    let actions: IslandActions
    @FocusState private var searchFocused: Bool

    var body: some View {
        let p = island.palette
        let shape = RoundedRectangle(cornerRadius: Island.launchpadRadius, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(p.matteBackground)
                .overlay(shape.strokeBorder(p.rim, lineWidth: 1))
                .contentShape(shape)
                .onTapGesture { actions.closeLaunchpad() }
            VStack(spacing: 0) {
                topRow
                Spacer().frame(height: 22)
                LaunchpadGrid(island: island, actions: actions, cellWidth: cellWidth)
                Spacer().frame(height: 10)
                pager
            }
            .padding(.top, island.notchSize.height + 12)
            .padding(.horizontal, Island.launchpadInset)
        }
        .frame(width: island.launchpadWidth, height: island.launchpadHeight)
        .onAppear { searchFocused = true }
    }

    private var cellWidth: CGFloat {
        (island.launchpadWidth - 2 * Island.launchpadInset) / CGFloat(Island.launchpadColumns)
    }

    private var query: Binding<String> {
        Binding(get: { island.launchpadQuery }, set: { island.launchpadQuery = $0; island.launchpadPage = 0 })
    }

    private var topRow: some View {
        let p = island.palette
        return ZStack {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.matteSecondary)
                TextField("Search", text: query)
                    .textFieldStyle(.plain)
                    .font(Theme.font(13.5))
                    .foregroundStyle(p.matteLabel)
                    .focused($searchFocused)
                    .onSubmit { actions.launchFirst() }
                    .onExitCommand { actions.launchpadEscape() }
                    .onKeyPress(.leftArrow) { turnPage(-1) }
                    .onKeyPress(.rightArrow) { turnPage(1) }
            }
            .padding(.horizontal, 12)
            .frame(width: 270, height: Island.launchpadSearchHeight)
            .background(Capsule().fill(p.matteTile))
            .overlay(Capsule().strokeBorder(searchFocused ? p.matteAccent.opacity(0.6) : p.rim, lineWidth: 1))
            HStack(spacing: 6) {
                Spacer()
                LaunchpadTool(symbol: "gearshape", palette: p) { actions.openMenu() }
                LaunchpadTool(symbol: "circle.lefthalf.filled", palette: p) { actions.toggleTheme() }
                LaunchpadTool(symbol: "xmark", palette: p) { actions.closeLaunchpad() }
            }
        }
        .frame(height: Island.launchpadSearchHeight)
    }

    /// Arrow keys turn pages only while nothing is typed; otherwise they move the cursor as usual.
    private func turnPage(_ delta: Int) -> KeyPress.Result {
        guard island.launchpadQuery.isEmpty else { return .ignored }
        actions.launchpadStep(delta)
        return .handled
    }

    private var pager: some View {
        let p = island.palette
        let count = island.launchpadPageCount
        return HStack(spacing: 14) {
            pageArrow("chevron.left", -1, enabled: count > 1)
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { index in
                    Circle().fill(index == min(island.launchpadPage, count - 1) ? p.matteLabel : p.matteSecondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            pageArrow("chevron.right", 1, enabled: count > 1)
        }
        .frame(height: 16)
    }

    private func pageArrow(_ symbol: String, _ delta: Int, enabled: Bool) -> some View {
        Button { actions.launchpadStep(delta) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(island.palette.matteSecondary).frame(width: 20, height: 16)
        }
        .buttonStyle(PressStyle())
        .opacity(enabled ? 1 : 0)
    }
}

struct LaunchpadTool: View {
    let symbol: String
    let palette: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.matteSecondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.matteTile))
        }
        .buttonStyle(PressStyle())
    }
}

/// 8 × 4 cells of the current page. Fixed cell sizes so nothing moves while icons arrive.
struct LaunchpadGrid: View {
    var island: Island
    let actions: IslandActions
    let cellWidth: CGFloat

    var body: some View {
        let apps = island.launchpadPageApps
        let searching = !island.launchpadQuery.isEmpty
        VStack(spacing: 0) {
            if apps.isEmpty {
                Text(island.apps.scanned ? "No apps match" : "Reading your apps…")
                    .font(Theme.font(13)).foregroundStyle(island.palette.matteSecondary)
                    .frame(height: CGFloat(Island.launchpadRows) * Island.launchpadCell)
            } else {
                ForEach(0..<Island.launchpadRows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<Island.launchpadColumns, id: \.self) { column in
                            let index = row * Island.launchpadColumns + column
                            if index < apps.count {
                                LaunchpadCell(app: apps[index], island: island, actions: actions,
                                              highlighted: searching && index == 0 && island.launchpadPage == 0)
                                    .frame(width: cellWidth, height: Island.launchpadCell)
                            } else {
                                Color.clear.frame(width: cellWidth, height: Island.launchpadCell)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: CGFloat(Island.launchpadRows) * Island.launchpadCell)
    }
}

struct LaunchpadCell: View {
    let app: AppEntry
    var island: Island
    let actions: IslandActions
    var highlighted = false

    var body: some View {
        let p = island.palette
        Button { actions.launch(app) } label: {
            VStack(spacing: 7) {
                Group {
                    if let icon = island.apps.icon(for: app) {
                        Image(nsImage: icon).resizable()
                    } else {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(p.matteTile)
                    }
                }
                .frame(width: AppCatalog.iconPoints, height: AppCatalog.iconPoints)
                Text(app.name).font(Theme.font(11)).foregroundStyle(p.matteLabel)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(highlighted ? p.matteTile : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(app.name)
    }
}
