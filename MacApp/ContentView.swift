//
//  ContentView.swift
//  MacApp
//
//  Created by 252的Macbook Air on 2026/3/1.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var root: AppItem
    @State private var currentPath: [UUID]
    @State private var isDroppingToParent: Bool = false
    @State private var searchText: String = ""
    @State private var pageIndexByContainer: [UUID: Int] = [:]
    @State private var dragOffsetByContainer: [UUID: CGFloat] = [:]

    init() {
        let library = AppLibraryBuilder.build(layout: AppLayoutStore.load())
        _root = State(initialValue: library)
        _currentPath = State(initialValue: [library.id])
    }

    var body: some View {
        ZStack {
            LaunchpadBackground()
            VStack(spacing: 16) {
                searchBar
                appGrid(
                    items: filteredItems(for: root.children),
                    pageKey: root.id,
                    isInteractionEnabled: currentPath.count == 1
                )
            }
            .padding(20)

            if currentPath.count > 1, let folder = currentFolder() {
                folderOverlay(folder: folder)
            }
        }
        .background(EscapeKeyHandler {
            NSApp.hide(nil)
        })
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用或文件夹", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .glassEffect(in: .rect(cornerRadius: 14))
        )
        .frame(maxWidth: 420)
    }

    private func appGrid(items: [AppItem], pageKey: UUID, isInteractionEnabled: Bool) -> some View {
        GeometryReader { proxy in
            let columnsCount = 7
            let rowsCount = 5
            let columnSpacing: CGFloat = 30
            let rowSpacing: CGFloat = 34
            let horizontalPadding: CGFloat = 24
            let topPadding: CGFloat = 8
            let bottomPadding: CGFloat = 52
            let cellWidth = max((proxy.size.width - horizontalPadding * 2 - columnSpacing * CGFloat(columnsCount - 1)) / CGFloat(columnsCount), 80)
            let cellHeight = max((proxy.size.height - topPadding - bottomPadding - rowSpacing * CGFloat(rowsCount - 1)) / CGFloat(rowsCount), 100)
            let pageSize = columnsCount * rowsCount
            let pages = pagedItems(for: items, pageSize: pageSize)
            let gridColumns = Array(repeating: GridItem(.fixed(cellWidth), spacing: columnSpacing), count: columnsCount)
            let currentPage = clampedPageIndex(for: pageKey, pageCount: pages.count)
            let dragOffset = dragOffsetByContainer[pageKey] ?? 0
            let maxPage = max(pages.count - 1, 0)
            let pagingThreshold = proxy.size.width * 0.22

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageItems in
                        VStack(alignment: .leading, spacing: 0) {
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: rowSpacing) {
                                ForEach(pageItems) { item in
                                    AppTile(
                                        item: item,
                                        onOpenFolder: {
                                            if item.isFolder {
                                                currentPath.append(item.id)
                                            }
                                        }
                                    )
                                    .frame(width: cellWidth, height: cellHeight, alignment: .top)
                                    .onDrag {
                                        NSItemProvider(object: item.id.uuidString as NSString)
                                    }
                                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                                        handleDrop(providers: providers, target: item, moveToParent: false)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: proxy.size.width)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, topPadding)
                        .id(pageIndex)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: -CGFloat(currentPage) * proxy.size.width + dragOffset)
                .animation(.snappy, value: currentPage)
                .contentShape(Rectangle())
                .clipped()
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            guard isInteractionEnabled else { return }
                            dragOffsetByContainer[pageKey] = value.translation.width
                        }
                        .onEnded { value in
                            guard isInteractionEnabled else { return }
                            let predicted = value.predictedEndTranslation.width
                            let actual = value.translation.width
                            let movingLeft = predicted < -pagingThreshold || actual < -pagingThreshold
                            let movingRight = predicted > pagingThreshold || actual > pagingThreshold

                            if movingLeft {
                                pageIndexByContainer[pageKey] = min(max(currentPage + 1, 0), maxPage)
                            } else if movingRight {
                                pageIndexByContainer[pageKey] = min(max(currentPage - 1, 0), maxPage)
                            } else {
                                pageIndexByContainer[pageKey] = min(max(currentPage, 0), maxPage)
                            }

                            withAnimation(.snappy) {
                                dragOffsetByContainer[pageKey] = 0
                            }
                        }
                )

                if isInteractionEnabled {
                    TrackpadPagingMonitor {
                        delta in
                        guard pages.count > 1 else { return }
                        withAnimation(.snappy) {
                            pageIndexByContainer[pageKey] = min(max(currentPage + delta, 0), maxPage)
                            dragOffsetByContainer[pageKey] = 0
                        }
                    }
                    .allowsHitTesting(false)
                }

                if pages.count > 1 {
                    pageIndicator(pageCount: pages.count, currentPage: currentPage) { targetPage in
                        withAnimation(.snappy) {
                            pageIndexByContainer[pageKey] = min(max(targetPage, 0), maxPage)
                            dragOffsetByContainer[pageKey] = 0
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers, target: nil, moveToParent: false)
        }
    }

    private func folderOverlay(folder: AppItem) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    currentPath = [root.id]
                }
                .onDrop(of: [UTType.plainText], isTargeted: $isDroppingToParent) { providers in
                    handleDrop(providers: providers, target: nil, moveToParent: true)
                }

            VStack(spacing: 16) {
                Text(folder.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                appGrid(items: filteredItems(for: folder.children), pageKey: folder.id, isInteractionEnabled: true)
            }
            .padding(26)
            .frame(maxWidth: 1500, maxHeight: 1120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.thinMaterial)
                    .glassEffect(in: .rect(cornerRadius: 26))
            )
        }
    }

    private func handleDrop(providers: [NSItemProvider], target: AppItem?, moveToParent: Bool) -> Bool {
        guard let provider = providers.first else { return false }
        let typeIdentifier = UTType.plainText.identifier

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { data, _ in
            let idString: String?
            if let data = data as? Data {
                idString = String(data: data, encoding: .utf8)
            } else if let text = data as? String {
                idString = text
            } else if let text = data as? NSString {
                idString = text as String
            } else {
                idString = nil
            }

            guard let idString, let itemId = UUID(uuidString: idString) else { return }

            DispatchQueue.main.async {
                if moveToParent {
                    moveItem(itemId, toFolderId: parentFolderId())
                    return
                }

                if let target, target.isFolder {
                    moveItem(itemId, toFolderId: target.id)
                } else {
                    let destinationFolderId = currentFolderId()
                    let insertBefore = target?.id
                    moveItem(itemId, toFolderId: destinationFolderId, insertBefore: insertBefore)
                }
            }
        }

        return true
    }

    private func folderName(for id: UUID) -> String {
        if let item = root.findItem(id: id) {
            return item.name
        }
        return "应用"
    }

    private func currentFolderId() -> UUID {
        currentPath.last ?? root.id
    }

    private func parentFolderId() -> UUID {
        guard currentPath.count > 1 else { return root.id }
        return currentPath[currentPath.count - 2]
    }

    private func currentFolder() -> AppItem? {
        root.findItem(id: currentFolderId())
    }

    private func filteredItems(for items: [AppItem]) -> [AppItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func pagedItems(for items: [AppItem], pageSize: Int) -> [[AppItem]] {
        guard pageSize > 0 else { return [items] }
        guard !items.isEmpty else { return [[]] }

        var pages: [[AppItem]] = []
        var startIndex = items.startIndex

        while startIndex < items.endIndex {
            let endIndex = min(startIndex + pageSize, items.endIndex)
            pages.append(Array(items[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return pages
    }

    private func clampedPageIndex(for pageKey: UUID, pageCount: Int) -> Int {
        let maxPage = max(pageCount - 1, 0)
        let current = pageIndexByContainer[pageKey] ?? 0
        return min(max(current, 0), maxPage)
    }

    private func pageIndicator(pageCount: Int, currentPage: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(index == currentPage ? Color.white.opacity(0.95) : Color.white.opacity(0.35))
                        .frame(width: index == currentPage ? 8 : 7, height: index == currentPage ? 8 : 7)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func moveItem(_ id: UUID, toFolderId: UUID, insertBefore: UUID? = nil) {
        guard id != toFolderId else { return }

        if let movingItem = root.findItem(id: id), movingItem.isFolder {
            if movingItem.contains(id: toFolderId) {
                return
            }
        }

        guard let item = root.removeItem(withId: id) else { return }
        let insertIndex = root.indexInFolder(folderId: toFolderId, beforeItemId: insertBefore)
        if root.insertItem(item, intoFolderId: toFolderId, at: insertIndex) {
            AppLayoutStore.save(root: root)
        }
    }
}

private struct AppTile: View {
    let item: AppItem
    let onOpenFolder: () -> Void
    private let folderTileSize: CGFloat = 76
    private let folderPreviewSize: CGFloat = 69
    private let appTileSize: CGFloat = 92

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if item.isFolder {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.34),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .glassEffect(in: .rect(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
                        .frame(width: folderTileSize, height: folderTileSize)
                }

                if item.isFolder {
                    FolderPreview(items: Array(item.children.prefix(12)))
                        .padding(6)
                        .frame(width: folderPreviewSize, height: folderPreviewSize)
                } else if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: appTileSize, height: appTileSize)
                        .shadow(color: .black.opacity(0.2), radius: 7, x: 0, y: 4)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: appTileSize, height: appTileSize)

            Text(item.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 138)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isFolder {
                onOpenFolder()
            } else if let url = item.appURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct FolderPreview: View {
    let items: [AppItem]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let totalSpacing = spacing * 3
            let cellSize = (min(proxy.size.width, proxy.size.height) - totalSpacing) / 4
            let columns = [
                GridItem(.fixed(cellSize), spacing: spacing),
                GridItem(.fixed(cellSize), spacing: spacing),
                GridItem(.fixed(cellSize), spacing: spacing),
                GridItem(.fixed(cellSize), spacing: spacing)
            ]

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(items) { item in
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: cellSize, height: cellSize)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LaunchpadBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.08, blue: 0.12),
                Color(red: 0.16, green: 0.16, blue: 0.22),
                Color(red: 0.08, green: 0.09, blue: 0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 380, height: 380)
                    .blur(radius: 60)
                    .offset(x: -240, y: -200)

                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 420, height: 420)
                    .blur(radius: 80)
                    .offset(x: 260, y: -140)

                RoundedRectangle(cornerRadius: 140, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 520, height: 260)
                    .blur(radius: 60)
                    .rotationEffect(.degrees(18))
                    .offset(x: -80, y: 220)
            }
        )
        .ignoresSafeArea()
    }
}

private struct TrackpadPagingMonitor: NSViewRepresentable {
    let onPageDelta: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageDelta: onPageDelta)
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        context.coordinator.onPageDelta = onPageDelta
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class MonitorView: NSView {}

    final class Coordinator {
        var onPageDelta: (Int) -> Void
        private weak var view: MonitorView?
        private var monitor: Any?
        private var accumulatedDeltaX: CGFloat = 0

        init(onPageDelta: @escaping (Int) -> Void) {
            self.onPageDelta = onPageDelta
        }

        func attach(to view: MonitorView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                guard let view = self.view, let window = view.window else { return event }

                let cursorInWindow = window.mouseLocationOutsideOfEventStream
                let cursorInView = view.convert(cursorInWindow, from: nil)
                guard view.bounds.contains(cursorInView) else { return event }

                let deltaX = event.scrollingDeltaX
                let deltaY = event.scrollingDeltaY
                guard abs(deltaX) > abs(deltaY), abs(deltaX) > 0 else { return event }

                accumulatedDeltaX += deltaX
                let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 32 : 3

                if accumulatedDeltaX >= threshold {
                    onPageDelta(-1)
                    accumulatedDeltaX = 0
                    return nil
                }

                if accumulatedDeltaX <= -threshold {
                    onPageDelta(1)
                    accumulatedDeltaX = 0
                    return nil
                }

                return nil
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

private struct EscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EscapeKeyCaptureView()
        view.onEscape = onEscape
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? EscapeKeyCaptureView else { return }
        view.onEscape = onEscape
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}

private final class EscapeKeyCaptureView: NSView {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct AppItem: Identifiable {
    enum Kind {
        case app(URL)
        case folder
    }

    let id: UUID
    let cacheKey: String
    var name: String
    var kind: Kind
    var icon: NSImage?
    var children: [AppItem]

    var isFolder: Bool {
        if case .folder = kind {
            return true
        }
        return false
    }

    var appURL: URL? {
        if case .app(let url) = kind {
            return url
        }
        return nil
    }

    func findItem(id: UUID) -> AppItem? {
        if self.id == id {
            return self
        }
        for child in children {
            if let found = child.findItem(id: id) {
                return found
            }
        }
        return nil
    }

    func contains(id: UUID) -> Bool {
        if self.id == id {
            return true
        }
        for child in children {
            if child.contains(id: id) {
                return true
            }
        }
        return false
    }

    mutating func removeItem(withId id: UUID) -> AppItem? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            return children.remove(at: index)
        }
        for index in children.indices {
            if let removed = children[index].removeItem(withId: id) {
                return removed
            }
        }
        return nil
    }

    mutating func insertItem(_ item: AppItem, intoFolderId folderId: UUID, at index: Int?) -> Bool {
        if self.id == folderId {
            let insertIndex = min(index ?? children.count, children.count)
            children.insert(item, at: insertIndex)
            return true
        }
        for childIndex in children.indices {
            if children[childIndex].insertItem(item, intoFolderId: folderId, at: index) {
                return true
            }
        }
        return false
    }

    func indexInFolder(folderId: UUID, beforeItemId: UUID?) -> Int? {
        guard let beforeItemId else { return nil }
        if self.id == folderId {
            return children.firstIndex(where: { $0.id == beforeItemId })
        }
        for child in children {
            if let index = child.indexInFolder(folderId: folderId, beforeItemId: beforeItemId) {
                return index
            }
        }
        return nil
    }
}

private struct AppLayoutCache: Codable {
    let version: Int
    let containers: [String: [String]]

    init(version: Int = 1, containers: [String: [String]]) {
        self.version = version
        self.containers = containers
    }
}

private enum AppLayoutStore {
    private static let cacheFileName = "launchpad-layout-cache.json"

    static func load() -> AppLayoutCache? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(AppLayoutCache.self, from: data) else {
            return nil
        }
        return cache
    }

    static func save(root: AppItem) {
        var containers: [String: [String]] = [:]
        collectContainers(from: root, containers: &containers)

        guard let url = cacheURL(),
              let data = try? JSONEncoder().encode(AppLayoutCache(containers: containers)) else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private static func collectContainers(from item: AppItem, containers: inout [String: [String]]) {
        if item.isFolder {
            containers[item.cacheKey] = item.children.map(\.cacheKey)
        }
        for child in item.children {
            collectContainers(from: child, containers: &containers)
        }
    }

    private static func cacheURL() -> URL? {
        let fileManager = FileManager.default
        guard var appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "MacApp"
        appSupport.appendPathComponent(bundleId, isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent(cacheFileName)
    }
}

private enum AppLibraryBuilder {
    static func build(layout: AppLayoutCache?) -> AppItem {
        let rootId = UUID()
        var root = AppItem(id: rootId, cacheKey: "root", name: "应用", kind: .folder, icon: nil, children: [])

        let fileManager = FileManager.default
        let localApps = URL(fileURLWithPath: "/Applications")
        let appleApps = URL(fileURLWithPath: "/System/Applications")
        let userApps = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")

        let allSources = [localApps, appleApps, userApps]
        var collected: [AppItem] = []

        for source in allSources {
            collected.append(contentsOf: scanFolder(source))
        }

        root.children = uniqueItems(collected).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if let layout {
            apply(layout, to: &root)
        }

        return root
    }

    private static func scanFolder(_ url: URL) -> [AppItem] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [AppItem] = []

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey]) else { continue }
            guard values.isDirectory == true else { continue }

            if entry.pathExtension.lowercased() == "app" {
                let resolved = entry.resolvingSymlinksInPath()
                let name = resolved.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: resolved.path)
                let key = "app:\(resolved.path)"
                items.append(AppItem(id: UUID(), cacheKey: key, name: name, kind: .app(resolved), icon: icon, children: []))
            } else {
                let children = scanFolder(entry)
                if !children.isEmpty {
                    let resolved = entry.resolvingSymlinksInPath()
                    let icon = NSImage(named: NSImage.folderName)
                    let name = resolved.lastPathComponent
                    let key = "folder:\(resolved.path)"
                    let sortedChildren = children.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    items.append(AppItem(id: UUID(), cacheKey: key, name: name, kind: .folder, icon: icon, children: sortedChildren))
                }
            }
        }

        return items
    }

    private static func uniqueItems(_ items: [AppItem]) -> [AppItem] {
        var seen: Set<String> = []
        var result: [AppItem] = []
        for item in items where !seen.contains(item.cacheKey) {
            seen.insert(item.cacheKey)
            result.append(item)
        }
        return result
    }

    private static func apply(_ layout: AppLayoutCache, to root: inout AppItem) {
        let rootKey = root.cacheKey
        var nodesByKey: [String: AppItem] = [:]
        var defaultParent: [String: String] = [:]
        var defaultOrder: [String: [String: Int]] = [:]

        collectNodeData(
            root,
            parentKey: nil,
            orderInParent: nil,
            nodesByKey: &nodesByKey,
            defaultParent: &defaultParent,
            defaultOrder: &defaultOrder
        )

        let containerKeys = Set(nodesByKey.values.filter(\.isFolder).map(\.cacheKey))
        var parentAssignment = defaultParent

        func createsCycle(childKey: String, newParentKey: String, parents: [String: String]) -> Bool {
            guard nodesByKey[childKey]?.isFolder == true else { return false }
            var cursor: String? = newParentKey
            while let current = cursor {
                if current == childKey {
                    return true
                }
                cursor = parents[current]
            }
            return false
        }

        for (containerKey, orderedChildren) in layout.containers where containerKeys.contains(containerKey) {
            for childKey in orderedChildren {
                guard childKey != rootKey, nodesByKey[childKey] != nil else { continue }
                if createsCycle(childKey: childKey, newParentKey: containerKey, parents: parentAssignment) {
                    continue
                }
                parentAssignment[childKey] = containerKey
            }
        }

        var childrenByContainer: [String: [String]] = [:]
        for key in nodesByKey.keys where key != rootKey {
            let candidateParent = parentAssignment[key] ?? defaultParent[key] ?? rootKey
            let containerKey = containerKeys.contains(candidateParent) ? candidateParent : rootKey
            childrenByContainer[containerKey, default: []].append(key)
        }

        for containerKey in containerKeys {
            let cachedSequence = layout.containers[containerKey] ?? []
            var cachedIndex: [String: Int] = [:]
            for (index, key) in cachedSequence.enumerated() where cachedIndex[key] == nil {
                cachedIndex[key] = index
            }
            let defaultIndex = defaultOrder[containerKey] ?? [:]

            childrenByContainer[containerKey]?.sort { left, right in
                let leftCached = cachedIndex[left] ?? Int.max
                let rightCached = cachedIndex[right] ?? Int.max
                if leftCached != rightCached {
                    return leftCached < rightCached
                }

                let leftDefault = defaultIndex[left] ?? Int.max
                let rightDefault = defaultIndex[right] ?? Int.max
                if leftDefault != rightDefault {
                    return leftDefault < rightDefault
                }

                return (nodesByKey[left]?.name ?? "") < (nodesByKey[right]?.name ?? "")
            }
        }

        var rebuilding: Set<String> = []

        func rebuildNode(_ key: String) -> AppItem? {
            guard var node = nodesByKey[key] else { return nil }
            guard !rebuilding.contains(key) else {
                node.children = []
                return node
            }

            rebuilding.insert(key)
            let childKeys = childrenByContainer[key] ?? []
            node.children = childKeys.compactMap { rebuildNode($0) }
            rebuilding.remove(key)
            return node
        }

        if let rebuiltRoot = rebuildNode(rootKey) {
            root = rebuiltRoot
        }
    }

    private static func collectNodeData(
        _ node: AppItem,
        parentKey: String?,
        orderInParent: Int?,
        nodesByKey: inout [String: AppItem],
        defaultParent: inout [String: String],
        defaultOrder: inout [String: [String: Int]]
    ) {
        var stripped = node
        stripped.children = []
        nodesByKey[node.cacheKey] = stripped

        if let parentKey {
            defaultParent[node.cacheKey] = parentKey
            if let orderInParent {
                var indices = defaultOrder[parentKey] ?? [:]
                indices[node.cacheKey] = orderInParent
                defaultOrder[parentKey] = indices
            }
        }

        for (index, child) in node.children.enumerated() {
            collectNodeData(
                child,
                parentKey: node.cacheKey,
                orderInParent: index,
                nodesByKey: &nodesByKey,
                defaultParent: &defaultParent,
                defaultOrder: &defaultOrder
            )
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 640)
}
