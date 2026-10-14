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
                if !island.visibleWidgets.isEmpty {
                    LaunchpadWidgets(island: island, actions: actions)
                    Spacer().frame(height: 18)
                }
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
            if let folder = island.launchpadFolder, island.launchpadCategories, island.launchpadQuery.isEmpty {
                HStack {
                    Button { actions.openFolder(nil) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                            Text(folder.title).font(Theme.font(13))
                        }
                        .foregroundStyle(p.matteLabel)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(p.matteTile))
                    }
                    .buttonStyle(PressStyle())
                    Spacer()
                }
            }
            HStack(spacing: 6) {
                Spacer()
                LaunchpadTool(symbol: "square.grid.2x2", on: island.launchpadCategories, palette: p) { actions.toggleCategories() }
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
    var on = false
    let palette: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? (palette.isDark ? Color.black : .white) : palette.matteSecondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? palette.matteAccent : palette.matteTile))
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
            if island.launchpadShowsFolders {
                HStack(spacing: 0) {
                    ForEach(island.apps.categories, id: \.self) { category in
                        LaunchpadFolderCell(category: category, island: island, actions: actions)
                            .frame(width: cellWidth, height: Island.launchpadCell)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else if apps.isEmpty {
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

/// A folder: the first four icons in a tile, the count in a badge, the name under it.
struct LaunchpadFolderCell: View {
    let category: AppCategory
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        let apps = island.apps.apps(in: category)
        Button { actions.openFolder(category) } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(p.matteTile)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                    VStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(0..<2, id: \.self) { column in
                                    let index = row * 2 + column
                                    if index < apps.count, let icon = island.apps.icon(for: apps[index]) {
                                        Image(nsImage: icon).resizable().frame(width: 19, height: 19)
                                    } else {
                                        Color.clear.frame(width: 19, height: 19)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: AppCatalog.iconPoints + 8, height: AppCatalog.iconPoints + 8)
                    Text("\(apps.count)").font(Theme.digits(10, .semibold))
                        .foregroundStyle(p.isDark ? Color.black : .white)
                        .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(p.matteAccent))
                        .offset(x: 5, y: -5)
                }
                .frame(width: AppCatalog.iconPoints + 8, height: AppCatalog.iconPoints + 8)
                Text(category.title).font(Theme.font(11)).foregroundStyle(p.matteLabel)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: 12))
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
        .buttonStyle(PressStyle(radius: 12))
        .help(app.name)
    }
}

// MARK: - Widgets

/// One row of widgets, centred, scaled down as one piece when they would not fit.
struct LaunchpadWidgets: View {
    var island: Island
    let actions: IslandActions

    var body: some View {
        let p = island.palette
        let scale = island.widgetScale
        HStack(spacing: Island.widgetGap) {
            ForEach(island.visibleWidgets, id: \.self) { widget in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.matteTile)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.rim, lineWidth: 1))
                    content(widget)
                }
                .frame(width: widget.width, height: Island.widgetHeight)
            }
        }
        .scaleEffect(scale, anchor: .top)
        .frame(height: (Island.widgetHeight * scale).rounded())
    }

    @ViewBuilder private func content(_ widget: LaunchpadWidget) -> some View {
        switch widget {
        case .nowPlaying:
            if let track = island.nowPlaying {
                NowPlayingWidget(track: track, palette: island.palette, actions: actions, live: !island.demo && !island.reduceMotion,
                                 progress: { [island] in island.nowPlayingIsSpotify ? island.spotifyModel.progress : island.musicModel.progress })
            }
        case .weather:
            if let weather = island.weather { WeatherWidget(weather: weather, palette: island.palette) }
        case .toggles:
            TogglesWidget(island: island)
        }
    }
}

struct NowPlayingWidget: View {
    let track: SpotifyTrack
    let palette: Palette
    let actions: IslandActions
    var live = false
    var progress: () -> Double = { 0 }

    private func bar(_ value: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(palette.matteSecondary.opacity(0.3))
            Capsule().fill(palette.matteSecondary).frame(width: max(0, min(1, value)) * 132)
        }
        .frame(width: 132, height: 3)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let art = track.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        palette.matteSecondary.opacity(0.25)
                        Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(palette.matteSecondary)
                    }
                }
            }
            .frame(width: 92, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(Theme.font(13.5, .semibold)).foregroundStyle(palette.matteLabel).lineLimit(1)
                Text(track.artist).font(Theme.font(12)).foregroundStyle(palette.matteSecondary).lineLimit(1)
                Group {
                    if track.playing && live {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in bar(progress()) }
                    } else {
                        bar(track.progress)
                    }
                }
                .padding(.top, 8)
                HStack(spacing: 22) {
                    control("backward.fill", .previous)
                    control(track.playing ? "pause.fill" : "play.fill", .playPause)
                    control("forward.fill", .next)
                }
                .frame(width: 132)
                .padding(.top, 6)
            }
            .frame(width: 132, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(height: Island.widgetHeight)
    }

    private func control(_ symbol: String, _ command: SpotifyCommand) -> some View {
        Button { actions.nowPlaying(command) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.matteLabel)
                .frame(width: 18, height: 16)
        }
        .buttonStyle(PressStyle())
    }
}

struct WeatherWidget: View {
    let weather: WeatherNow
    let palette: Palette

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(weather.temperature)°").font(Theme.digits(30, .medium)).foregroundStyle(palette.matteLabel)
                Text(weather.city).font(Theme.font(12.5)).foregroundStyle(palette.matteSecondary).lineLimit(1).padding(.top, 4)
                Text("H \(weather.high)°  L \(weather.low)°").font(Theme.digits(11)).foregroundStyle(palette.matteSecondary).padding(.top, 6)
            }
            Spacer(minLength: 4)
            Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 30))
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }
}

/// Wi-Fi, AirDrop, keyboard brightness down / up, dark mode and mute as buttons, the volume as a slider underneath.
struct TogglesWidget: View {
    var island: Island

    var body: some View {
        let p = island.palette
        let t = island.toggles
        let v = island.volume
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                toggle("wifi", on: t.wifiOn, enabled: t.wifiAvailable, help: "Wi-Fi") { t.toggleWifi() }
                toggle("square.and.arrow.up.circle", on: false, enabled: true, help: "AirDrop window") { t.openAirDrop() }
                toggle("light.min", on: false, enabled: Typist.isTrusted, help: Typist.isTrusted ? "Keyboard backlight down" : "Keyboard backlight needs Accessibility (Permissions menu)") { t.keyboardBrightness(up: false) }
                toggle("light.max", on: false, enabled: Typist.isTrusted, help: Typist.isTrusted ? "Keyboard backlight up" : "Keyboard backlight needs Accessibility (Permissions menu)") { t.keyboardBrightness(up: true) }
                toggle("circle.lefthalf.filled", on: t.darkMode, enabled: true, help: "Dark mode") { t.toggleDarkMode() }
                toggle(v.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", on: !v.muted, enabled: v.available, help: "Mute") { v.toggleMute() }
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.matteSecondary)
                Slider(value: Binding(get: { Double(v.level) }, set: { v.setLevel(Float($0)) }), in: 0...1)
                    .controlSize(.mini)
                    .tint(p.matteAccent)
                    .disabled(!v.hasLevel)
                Image(systemName: "speaker.wave.3").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.matteSecondary)
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private func toggle(_ symbol: String, on: Bool, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        let p = island.palette
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? (p.isDark ? Color.black : .white) : p.matteSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? p.matteAccent : p.matteSecondary.opacity(0.18)))
        }
        .buttonStyle(PressStyle(radius: 10))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }
}
