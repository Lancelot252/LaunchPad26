import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private let rootGridPageSize = 35

    private let onDismiss: () -> Void
    private let onLaunchApp: (URL) -> Void
    private let onResetLayout: () -> Void
    private let onOpenSettings: () -> Void
    @ObservedObject private var settingsStore: LaunchpadSettingsStore
    @Binding private var isEditing: Bool
    private let focusToken: UUID

    @State private var root: AppItem
    @State private var currentPath: [UUID]
    @State private var isDroppingToParent = false
    @State private var searchText = ""
    @State private var pageIndexByContainer: [UUID: Int] = [:]
    @State private var dragOffsetByContainer: [UUID: CGFloat] = [:]
    @State private var hiddenItemKeys: Set<String>
    @State private var folderNameDraft = ""
    @State private var isShowingSettingsPopover = false
    @State private var isShowingResetConfirmation = false
    @State private var editModeState = EditModeStateMachine()
    @FocusState private var isSearchFocused: Bool

    init(
        onDismiss: @escaping () -> Void = {},
        onLaunchApp: @escaping (URL) -> Void = { _ in },
        onResetLayout: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        settingsStore: LaunchpadSettingsStore = LaunchpadSettingsStore(),
        isEditing: Binding<Bool> = .constant(false),
        focusToken: UUID = UUID()
    ) {
        self.onDismiss = onDismiss
        self.onLaunchApp = onLaunchApp
        self.onResetLayout = onResetLayout
        self.onOpenSettings = onOpenSettings
        _settingsStore = ObservedObject(initialValue: settingsStore)
        _isEditing = isEditing
        self.focusToken = focusToken

        let layout = AppLayoutStore.load()
        let library = AppLibraryBuilder.build(layout: layout)
        _root = State(initialValue: library)
        _currentPath = State(initialValue: [library.id])
        _hiddenItemKeys = State(initialValue: Set(layout?.hiddenItemKeys ?? []))
    }

    var body: some View {
        ZStack {
            LaunchpadBackground()
                .contentShape(Rectangle())
                .onTapGesture {
                    handleBackgroundTap()
                }

            VStack(spacing: 16) {
                searchBar
                appGrid(
                    items: filteredItems(for: root.children),
                    pageKey: root.id,
                    isInteractionEnabled: currentPath.count == 1,
                    showsEmbeddedPageIndicator: false
                )
            }
            .padding(20)

            if currentPath.count > 1, let folder = currentFolder() {
                folderOverlay(folder: folder)
            }
        }
        .background(
            KeyEventCapture(
                onEscape: { handleEscapeKey() },
                onInsertText: { insertSearchText($0) },
                onDeleteBackward: { removeLastSearchCharacter() },
                onOptionChanged: { isOptionPressed in
                    handleOptionKeyChanged(isOptionPressed)
                }
            )
        )
        .onAppear {
            editModeState.syncExternalEditingState(isEditing)
            synchronizeFolderDraft()
            focusSearchField()
        }
        .onChange(of: isEditing) { _, newValue in
            editModeState.syncExternalEditingState(newValue)
        }
        .onChange(of: focusToken) { _, _ in
            focusSearchField()
        }
        .onChange(of: currentPath) { _, _ in
            synchronizeFolderDraft()
        }
        .alert("重建 Launchpad 布局？", isPresented: $isShowingResetConfirmation) {
            Button("取消", role: .cancel) { }
            Button("重建", role: .destructive) {
                resetLayout()
            }
        } message: {
            Text("这会清空当前布局排序与隐藏项，并重新扫描应用。")
        }
        .safeAreaInset(edge: .bottom) {
            if currentPath.count == 1 {
                rootPageIndicatorBar
                    .padding(.bottom, 26)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索应用或文件夹", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                isShowingSettingsPopover.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开设置")
            .popover(isPresented: $isShowingSettingsPopover, arrowEdge: .bottom) {
                InlineSettingsPanel(settingsStore: settingsStore) {
                    isShowingSettingsPopover = false
                    onOpenSettings()
                }
            }

            Button {
                requestResetLayout()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("重建 Launchpad 布局")

            if isEditing {
                Button("完成") {
                    exitEditingMode(userInitiated: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
                .glassEffect(in: .rect(cornerRadius: 14))
        )
        .frame(maxWidth: 460)
    }

    private func appGrid(
        items: [AppItem],
        pageKey: UUID,
        isInteractionEnabled: Bool,
        showsEmbeddedPageIndicator: Bool = true
    ) -> some View {
        GeometryReader { proxy in
            let columnsCount = 7
            let rowsCount = 5
            let baseCell: CGFloat = 150
            let baseColumnSpacing: CGFloat = 39
            let baseRowSpacing: CGFloat = 34
            let indicatorAreaHeight: CGFloat = 36
            let pageHorizontalInset: CGFloat = 20
            let pageVerticalInset: CGFloat = 8
            let referenceGridWidth = CGFloat(columnsCount) * baseCell + CGFloat(columnsCount - 1) * baseColumnSpacing
            let referenceGridHeight = CGFloat(rowsCount) * baseCell + CGFloat(rowsCount - 1) * baseRowSpacing
            let availableWidth = max(proxy.size.width - pageHorizontalInset * 2, 1)
            let availableHeight = max(proxy.size.height - indicatorAreaHeight - pageVerticalInset * 2, 1)
            let rawScale = min(availableWidth / referenceGridWidth, availableHeight / referenceGridHeight)
            let gridScale = min(max(rawScale, 0.72), 1.2)
            let cellWidth = max(baseCell * gridScale, 84)
            let cellHeight = max(baseCell * gridScale, 102)
            let columnSpacing = max(baseColumnSpacing * gridScale, 12)
            let rowSpacing = max(baseRowSpacing * gridScale, 14)
            let pageSize = columnsCount * rowsCount
            let pages = pagedItems(for: items, pageSize: pageSize)
            let gridColumns = Array(repeating: GridItem(.fixed(cellWidth), spacing: columnSpacing), count: columnsCount)
            let currentPage = clampedPageIndex(for: pageKey, pageCount: pages.count)
            let dragOffset = dragOffsetByContainer[pageKey] ?? 0
            let maxPage = max(pages.count - 1, 0)
            let pagingThreshold = proxy.size.width * 0.22
            let gridWidth = CGFloat(columnsCount) * cellWidth + CGFloat(columnsCount - 1) * columnSpacing
            let gridHeight = CGFloat(rowsCount) * cellHeight + CGFloat(rowsCount - 1) * rowSpacing
            let tileScale = min(cellWidth / 150, cellHeight / 150)

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageItems in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: rowSpacing) {
                                ForEach(0..<pageSize, id: \.self) { slotIndex in
                                    if slotIndex < pageItems.count {
                                        let item = pageItems[slotIndex]
                                        AppTile(
                                            item: item,
                                            isEditing: isEditing,
                                            onOpenFolder: {
                                                if item.isFolder {
                                                    currentPath.append(item.id)
                                                }
                                            },
                                            onOpenApp: { url in
                                                onLaunchApp(url)
                                            },
                                            onDelete: {
                                                hideItem(item.id)
                                            },
                                            onEnterEditMode: {
                                                enterEditingMode(trigger: .longPress)
                                            }
                                        )
                                        .scaleEffect(tileScale, anchor: .top)
                                        .frame(width: cellWidth, height: cellHeight, alignment: .top)
                                        .onDrag {
                                            NSItemProvider(object: item.id.uuidString as NSString)
                                        }
                                        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                                            handleDrop(providers: providers, target: item, moveToParent: false)
                                        }
                                    } else {
                                        Color.clear
                                            .frame(width: cellWidth, height: cellHeight)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                handleBackgroundTap()
                                            }
                                    }
                                }
                            }
                            .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
                            Spacer(minLength: 0)
                        }
                        .frame(width: proxy.size.width)
                        .frame(maxHeight: proxy.size.height - indicatorAreaHeight, alignment: .center)
                        .padding(.vertical, pageVerticalInset)
                        .id(pageIndex)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: -CGFloat(currentPage) * proxy.size.width + dragOffset)
                .animation(.snappy, value: currentPage)
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
                    TrackpadPagingMonitor { delta in
                        guard pages.count > 1 else { return }
                        withAnimation(.snappy) {
                            pageIndexByContainer[pageKey] = min(max(currentPage + delta, 0), maxPage)
                            dragOffsetByContainer[pageKey] = 0
                        }
                    }
                    .allowsHitTesting(false)
                }

                if showsEmbeddedPageIndicator && pages.count > 0 {
                    pageIndicator(pageCount: pages.count, currentPage: currentPage) { targetPage in
                        withAnimation(.snappy) {
                            pageIndexByContainer[pageKey] = min(max(targetPage, 0), maxPage)
                            dragOffsetByContainer[pageKey] = 0
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers, target: nil, moveToParent: false)
        }
    }

    private func folderOverlay(folder: AppItem) -> some View {
        GeometryReader { proxy in
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
                    TextField("文件夹", text: $folderNameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .onSubmit {
                            renameCurrentFolderIfNeeded()
                        }

                    appGrid(
                        items: filteredItems(for: folder.children),
                        pageKey: folder.id,
                        isInteractionEnabled: true
                    )
                }
                .padding(26)
                .frame(width: proxy.size.width * 0.8, height: proxy.size.height * 0.8)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.thinMaterial)
                        .glassEffect(in: .rect(cornerRadius: 26))
                )
            }
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
                    return
                }

                if let target,
                   createFolderFromDropIfNeeded(itemId: itemId, targetId: target.id, destinationFolderId: currentFolderId()) {
                    return
                }

                let destinationFolderId = currentFolderId()
                let insertBefore = target?.id
                moveItem(itemId, toFolderId: destinationFolderId, insertBefore: insertBefore)
            }
        }

        return true
    }

    private func createFolderFromDropIfNeeded(itemId: UUID, targetId: UUID, destinationFolderId: UUID) -> Bool {
        guard itemId != targetId,
              let source = root.findItem(id: itemId),
              let target = root.findItem(id: targetId),
              !source.isFolder,
              !target.isFolder,
              let sourceParent = root.parentId(of: itemId),
              let targetParent = root.parentId(of: targetId),
              sourceParent == targetParent,
              sourceParent == destinationFolderId else {
            return false
        }

        let sourceIndex = root.indexInFolder(folderId: sourceParent, beforeItemId: itemId)
        let targetIndex = root.indexInFolder(folderId: sourceParent, beforeItemId: targetId)

        guard let sourceItem = root.removeItem(withId: itemId),
              let targetItem = root.removeItem(withId: targetId) else {
            return false
        }

        let insertIndex: Int?
        if let sourceIndex, let targetIndex {
            insertIndex = min(sourceIndex, targetIndex)
        } else {
            insertIndex = nil
        }

        let orderedItems: [AppItem]
        if let sourceIndex, let targetIndex {
            orderedItems = sourceIndex <= targetIndex ? [sourceItem, targetItem] : [targetItem, sourceItem]
        } else {
            orderedItems = [targetItem, sourceItem]
        }

        let folderId = UUID()
        let folder = AppItem(
            id: folderId,
            cacheKey: "user-folder:\(folderId.uuidString)",
            name: "文件夹",
            kind: .folder,
            icon: NSImage(named: NSImage.folderName),
            children: orderedItems
        )

        guard root.insertItem(folder, intoFolderId: sourceParent, at: insertIndex) else {
            return false
        }

        saveLayout()
        return true
    }

    private func synchronizeFolderDraft() {
        if let folder = currentFolder(), folder.id != root.id {
            folderNameDraft = folder.name
        }
    }

    private func renameCurrentFolderIfNeeded() {
        guard let folder = currentFolder(), folder.id != root.id else { return }
        let trimmed = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "文件夹" : trimmed
        guard finalName != folder.name else { return }

        if root.renameItem(id: folder.id, name: finalName) {
            folderNameDraft = finalName
            saveLayout()
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func handleBackgroundTap() {
        if currentPath.count > 1 {
            currentPath = [root.id]
            return
        }

        if isEditing {
            return
        }

        onDismiss()
    }

    private func handleEscapeKey() {
        if isEditing {
            exitEditingMode(userInitiated: true)
            return
        }

        if currentPath.count > 1 {
            currentPath = [root.id]
            return
        }

        if !searchText.isEmpty {
            searchText = ""
            return
        }

        onDismiss()
    }

    private func enterEditingMode(trigger: EditModeEnterTrigger) {
        guard editModeState.enterEditingMode(trigger: trigger) else { return }
        isEditing = true
    }

    private func exitEditingMode(userInitiated: Bool) {
        let optionPressedNow = editModeState.isOptionPressed || NSEvent.modifierFlags.contains(.option)
        editModeState.forceExitEditingMode(userInitiated: userInitiated, optionPressedAtExit: optionPressedNow)
        isEditing = false
    }

    private func handleOptionKeyChanged(_ isOptionPressed: Bool) {
        guard editModeState.handleOptionChanged(isOptionPressed) else { return }
        if editModeState.isEditing {
            isEditing = true
        }
    }

    private func insertSearchText(_ value: String) {
        guard !isEditing else { return }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchText.append(value)
        isSearchFocused = true
    }

    private func removeLastSearchCharacter() {
        guard !searchText.isEmpty else { return }
        searchText.removeLast()
    }

    private func hideItem(_ id: UUID) {
        guard let removed = root.removeItem(withId: id) else { return }
        hiddenItemKeys.insert(removed.cacheKey)
        root.removeEmptyFolders(keepingRootId: root.id)
        ensureCurrentPathIsValid()
        saveLayout()
    }

    private func resetLayout() {
        isShowingResetConfirmation = false
        hiddenItemKeys.removeAll()
        root = AppLibraryBuilder.build(layout: nil)
        currentPath = [root.id]
        searchText = ""
        pageIndexByContainer.removeAll()
        dragOffsetByContainer.removeAll()
        editModeState.syncExternalEditingState(false)
        isEditing = false
        saveLayout()
        onResetLayout()
    }

    private func requestResetLayout() {
        if settingsStore.current.confirmBeforeResetLayout {
            isShowingResetConfirmation = true
        } else {
            resetLayout()
        }
    }

    private func ensureCurrentPathIsValid() {
        let validPath = currentPath.filter { root.findItem(id: $0) != nil }
        if validPath.isEmpty {
            currentPath = [root.id]
        } else {
            currentPath = validPath
        }
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

    private var rootPageGroups: [[AppItem]] {
        pagedItems(for: filteredItems(for: root.children), pageSize: rootGridPageSize)
    }

    private var rootCurrentPage: Int {
        clampedPageIndex(for: root.id, pageCount: rootPageGroups.count)
    }

    private var rootPageIndicatorBar: some View {
        let pageCount = rootPageGroups.count
        return Group {
            if pageCount > 0 {
                VStack(spacing: 6) {
                    pageIndicator(pageCount: pageCount, currentPage: rootCurrentPage) { targetPage in
                        withAnimation(.snappy) {
                            pageIndexByContainer[root.id] = min(max(targetPage, 0), max(pageCount - 1, 0))
                            dragOffsetByContainer[root.id] = 0
                        }
                    }

                    Text("\(rootCurrentPage + 1) / \(pageCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(true)
            }
        }
    }

    private func pageIndicator(pageCount: Int, currentPage: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(index == currentPage ? Color.white.opacity(0.95) : Color.white.opacity(0.45))
                        .frame(width: index == currentPage ? 9 : 7, height: index == currentPage ? 9 : 7)
                        .scaleEffect(index == currentPage ? 1 : 0.9)
                        .animation(.snappy, value: currentPage)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
    }

    private func moveItem(_ id: UUID, toFolderId: UUID, insertBefore: UUID? = nil) {
        guard id != toFolderId else { return }

        if let movingItem = root.findItem(id: id), movingItem.isFolder, movingItem.contains(id: toFolderId) {
            return
        }

        guard let item = root.removeItem(withId: id) else { return }
        let insertIndex = root.indexInFolder(folderId: toFolderId, beforeItemId: insertBefore)
        if root.insertItem(item, intoFolderId: toFolderId, at: insertIndex) {
            root.removeEmptyFolders(keepingRootId: root.id)
            ensureCurrentPathIsValid()
            saveLayout()
        }
    }

    private func saveLayout() {
        AppLayoutStore.save(root: root, hiddenKeys: Array(hiddenItemKeys))
    }
}

private struct AppTile: View {
    let item: AppItem
    let isEditing: Bool
    let onOpenFolder: () -> Void
    let onOpenApp: (URL) -> Void
    let onDelete: () -> Void
    let onEnterEditMode: () -> Void

    @State private var suppressNextTap = false
    @State private var isPressingForEdit = false

    private let folderTileSize: CGFloat = 76
    private let folderPreviewSize: CGFloat = 69
    private let appTileSize: CGFloat = 92

    private var wobbleAmplitude: Double {
        1.1 + Double(abs(item.id.hashValue % 4)) * 0.25
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isEditing)) { timeline in
            tileContent
                .rotationEffect(.degrees(wobbleAngle(at: timeline.date)))
        }
    }

    private var tileContent: some View {
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

                if isEditing {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .offset(x: appTileSize * 0.35, y: -appTileSize * 0.34)
                }
            }
            .frame(width: appTileSize, height: appTileSize)
            .contentShape(Rectangle())
            .scaleEffect(isPressingForEdit ? 0.94 : 1.0)
            .brightness(isPressingForEdit ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: isPressingForEdit)
            .onLongPressGesture(
                minimumDuration: 0.45,
                maximumDistance: 16,
                pressing: { isPressing in
                    guard !isEditing else {
                        isPressingForEdit = false
                        return
                    }
                    isPressingForEdit = isPressing
                },
                perform: {
                    isPressingForEdit = false
                    suppressNextTap = true
                    onEnterEditMode()
                }
            )

            Text(item.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 138)
        }
        .contentShape(Rectangle())
        .onChange(of: isEditing) { _, newValue in
            isPressingForEdit = false
            if !newValue {
                suppressNextTap = false
            }
        }
        .onTapGesture {
            if suppressNextTap {
                suppressNextTap = false
                return
            }

            if item.isFolder {
                onOpenFolder()
                return
            }

            if isEditing {
                return
            }

            if let url = item.appURL {
                onOpenApp(url)
            }
        }
    }

    private func wobbleAngle(at date: Date) -> Double {
        guard isEditing else { return 0 }
        let phaseSeed = Double(abs(item.id.hashValue % 10_000)) * 0.001
        let time = date.timeIntervalSinceReferenceDate
        return sin(time * 12 + phaseSeed) * wobbleAmplitude
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
        private var isGestureActive = false
        private var didTriggerPageForCurrentGesture = false

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

                let phase = event.phase
                let momentumPhase = event.momentumPhase
                let didBeginGesture = phase == .began || momentumPhase == .began
                let didEndGesture = phase == .ended || phase == .cancelled || momentumPhase == .ended || momentumPhase == .cancelled

                if didBeginGesture {
                    isGestureActive = true
                    didTriggerPageForCurrentGesture = false
                    accumulatedDeltaX = 0
                } else if !isGestureActive {
                    isGestureActive = true
                    didTriggerPageForCurrentGesture = false
                    accumulatedDeltaX = 0
                }

                let deltaX = event.scrollingDeltaX
                let deltaY = event.scrollingDeltaY
                guard abs(deltaX) > abs(deltaY) * 1.5, abs(deltaX) > 0 else {
                    if didEndGesture {
                        isGestureActive = false
                        didTriggerPageForCurrentGesture = false
                        accumulatedDeltaX = 0
                    }
                    return event
                }

                if didTriggerPageForCurrentGesture {
                    if didEndGesture {
                        isGestureActive = false
                        didTriggerPageForCurrentGesture = false
                        accumulatedDeltaX = 0
                    }
                    return nil
                }

                if accumulatedDeltaX != 0, (accumulatedDeltaX > 0) != (deltaX > 0) {
                    accumulatedDeltaX = deltaX
                } else {
                    accumulatedDeltaX += deltaX
                }

                let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 120 : 12

                if accumulatedDeltaX >= threshold {
                    onPageDelta(-1)
                    didTriggerPageForCurrentGesture = true
                    accumulatedDeltaX = 0
                    return nil
                }

                if accumulatedDeltaX <= -threshold {
                    onPageDelta(1)
                    didTriggerPageForCurrentGesture = true
                    accumulatedDeltaX = 0
                    return nil
                }

                if didEndGesture {
                    isGestureActive = false
                    didTriggerPageForCurrentGesture = false
                    accumulatedDeltaX = 0
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

private struct KeyEventCapture: NSViewRepresentable {
    let onEscape: () -> Void
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void
    let onOptionChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onEscape: onEscape,
            onInsertText: onInsertText,
            onDeleteBackward: onDeleteBackward,
            onOptionChanged: onOptionChanged
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = KeyEventCaptureView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
        context.coordinator.onInsertText = onInsertText
        context.coordinator.onDeleteBackward = onDeleteBackward
        context.coordinator.onOptionChanged = onOptionChanged
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onEscape: () -> Void
        var onInsertText: (String) -> Void
        var onDeleteBackward: () -> Void
        var onOptionChanged: (Bool) -> Void
        private weak var view: KeyEventCaptureView?
        private var monitor: Any?

        init(
            onEscape: @escaping () -> Void,
            onInsertText: @escaping (String) -> Void,
            onDeleteBackward: @escaping () -> Void,
            onOptionChanged: @escaping (Bool) -> Void
        ) {
            self.onEscape = onEscape
            self.onInsertText = onInsertText
            self.onDeleteBackward = onDeleteBackward
            self.onOptionChanged = onOptionChanged
        }

        func attach(to view: KeyEventCaptureView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                guard let view = self.view else { return event }
                guard let window = view.window, event.window == window else { return event }

                if event.type == .flagsChanged {
                    self.onOptionChanged(event.modifierFlags.contains(.option))
                    return event
                }

                if window.firstResponder is NSTextView {
                    return event
                }

                if event.keyCode == 53 {
                    self.onEscape()
                    return nil
                }

                if event.keyCode == 51 || event.keyCode == 117 {
                    self.onDeleteBackward()
                    return nil
                }

                let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .function]
                if !event.modifierFlags.intersection(blockedModifiers).isEmpty {
                    return event
                }

                guard let characters = event.charactersIgnoringModifiers,
                      !characters.isEmpty else {
                    return event
                }

                let allowed = characters.unicodeScalars.allSatisfy { scalar in
                    scalar.properties.isAlphabetic
                        || scalar.properties.isWhitespace
                        || scalar.properties.numericType != nil
                        || scalar.properties.generalCategory == .otherPunctuation
                        || scalar.properties.generalCategory == .dashPunctuation
                        || scalar.properties.generalCategory == .mathSymbol
                }

                if allowed {
                    self.onInsertText(characters)
                    return nil
                }

                return event
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

private final class KeyEventCaptureView: NSView {
}

struct AppItem: Identifiable {
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

    func parentId(of childId: UUID) -> UUID? {
        if children.contains(where: { $0.id == childId }) {
            return id
        }
        for child in children {
            if let found = child.parentId(of: childId) {
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

    mutating func renameItem(id: UUID, name: String) -> Bool {
        if self.id == id {
            self.name = name
            return true
        }

        for index in children.indices {
            if children[index].renameItem(id: id, name: name) {
                return true
            }
        }

        return false
    }

    mutating func removeEmptyFolders(keepingRootId: UUID) {
        for index in children.indices.reversed() {
            children[index].removeEmptyFolders(keepingRootId: keepingRootId)
            if children[index].isFolder && children[index].children.isEmpty && children[index].id != keepingRootId {
                children.remove(at: index)
            }
        }
    }

    mutating func removeItems(withCacheKeys keys: Set<String>) {
        for index in children.indices.reversed() {
            if keys.contains(children[index].cacheKey) {
                children.remove(at: index)
                continue
            }
            children[index].removeItems(withCacheKeys: keys)
        }
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

struct AppLayoutCache: Codable {
    let version: Int
    let containers: [String: [String]]
    let hiddenItemKeys: [String]

    init(version: Int = 2, containers: [String: [String]], hiddenItemKeys: [String] = []) {
        self.version = version
        self.containers = containers
        self.hiddenItemKeys = hiddenItemKeys
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        containers = try container.decodeIfPresent([String: [String]].self, forKey: .containers) ?? [:]
        hiddenItemKeys = try container.decodeIfPresent([String].self, forKey: .hiddenItemKeys) ?? []
    }
}

enum AppLayoutStore {
    private static let cacheFileName = "launchpad-layout-cache.json"

    static func load() -> AppLayoutCache? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(AppLayoutCache.self, from: data) else {
            return nil
        }
        return cache
    }

    static func save(root: AppItem, hiddenKeys: [String]) {
        var containers: [String: [String]] = [:]
        collectContainers(from: root, containers: &containers)

        let normalizedHiddenKeys = Array(Set(hiddenKeys)).sorted()

        guard let url = cacheURL(),
              let data = try? JSONEncoder().encode(
                AppLayoutCache(
                    version: 2,
                    containers: containers,
                    hiddenItemKeys: normalizedHiddenKeys
                )
              ) else {
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

enum AppLibraryBuilder {
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
            let hiddenKeys = Set(layout.hiddenItemKeys)
            if !hiddenKeys.isEmpty {
                root.removeItems(withCacheKeys: hiddenKeys)
            }
            root.removeEmptyFolders(keepingRootId: root.id)
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
