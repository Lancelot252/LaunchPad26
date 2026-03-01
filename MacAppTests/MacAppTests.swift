import Foundation
import Carbon.HIToolbox
import Testing
@testable import MacApp

struct MacAppTests {

    @Test func decodesVersion1LayoutCacheWithoutHiddenKeys() throws {
        let raw = """
        {
          "version": 1,
          "containers": {
            "root": ["app:/Applications/Calculator.app"]
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppLayoutCache.self, from: raw)

        #expect(decoded.version == 1)
        #expect(decoded.containers["root"] == ["app:/Applications/Calculator.app"])
        #expect(decoded.hiddenItemKeys.isEmpty)
    }

    @Test func decodesVersion2LayoutCacheWithHiddenKeys() throws {
        let raw = """
        {
          "version": 2,
          "containers": {
            "root": ["folder:/Applications/Utilities"]
          },
          "hiddenItemKeys": ["app:/Applications/Chess.app", "app:/Applications/News.app"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppLayoutCache.self, from: raw)

        #expect(decoded.version == 2)
        #expect(decoded.hiddenItemKeys.count == 2)
        #expect(decoded.hiddenItemKeys.contains("app:/Applications/Chess.app"))
        #expect(decoded.hiddenItemKeys.contains("app:/Applications/News.app"))
    }

    @Test func removesHiddenItemsAndPrunesEmptyFolders() {
        let appA = AppItem(
            id: UUID(),
            cacheKey: "app:A",
            name: "App A",
            kind: .app(URL(fileURLWithPath: "/Applications/AppA.app")),
            icon: nil,
            children: []
        )

        let hiddenApp = AppItem(
            id: UUID(),
            cacheKey: "app:hidden",
            name: "Hidden",
            kind: .app(URL(fileURLWithPath: "/Applications/Hidden.app")),
            icon: nil,
            children: []
        )

        let emptyFolder = AppItem(
            id: UUID(),
            cacheKey: "folder:empty",
            name: "Empty Folder",
            kind: .folder,
            icon: nil,
            children: [hiddenApp]
        )

        var root = AppItem(
            id: UUID(),
            cacheKey: "root",
            name: "应用",
            kind: .folder,
            icon: nil,
            children: [appA, emptyFolder]
        )

        root.removeItems(withCacheKeys: ["app:hidden"])
        root.removeEmptyFolders(keepingRootId: root.id)

        #expect(root.children.count == 1)
        #expect(root.children.first?.cacheKey == "app:A")
    }

    @Test func renameAndParentLookupWorkForNestedItems() {
        let nestedApp = AppItem(
            id: UUID(),
            cacheKey: "app:nested",
            name: "Nested",
            kind: .app(URL(fileURLWithPath: "/Applications/Nested.app")),
            icon: nil,
            children: []
        )

        let folder = AppItem(
            id: UUID(),
            cacheKey: "folder:test",
            name: "Folder",
            kind: .folder,
            icon: nil,
            children: [nestedApp]
        )

        var root = AppItem(
            id: UUID(),
            cacheKey: "root",
            name: "应用",
            kind: .folder,
            icon: nil,
            children: [folder]
        )

        let parentId = root.parentId(of: nestedApp.id)
        #expect(parentId == folder.id)

        let renamed = root.renameItem(id: folder.id, name: "Renamed Folder")
        #expect(renamed)
        #expect(root.findItem(id: folder.id)?.name == "Renamed Folder")
    }

    @Test func launchpadSettingsDefaultsAreExpected() {
        let defaults = LaunchpadSettings()
        #expect(defaults.hotkeyPreset == .f4)
        #expect(defaults.enableAnimations)
        #expect(defaults.hideOnResignActive)
        #expect(defaults.confirmBeforeResetLayout)
    }

    @Test func hotkeyPresetMappingIsCorrect() {
        #expect(LaunchpadHotkeyPreset.f4.keyCode == UInt32(kVK_F4))
        #expect(LaunchpadHotkeyPreset.f4.modifiers == 0)

        #expect(LaunchpadHotkeyPreset.optionSpace.keyCode == UInt32(kVK_Space))
        #expect(LaunchpadHotkeyPreset.optionSpace.modifiers == UInt32(optionKey))

        #expect(LaunchpadHotkeyPreset.commandShiftL.keyCode == UInt32(kVK_ANSI_L))
        #expect(LaunchpadHotkeyPreset.commandShiftL.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func settingsStorePersistsAndReloads() {
        let suiteName = "MacAppTests.Settings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false)
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = LaunchpadSettingsStore(userDefaults: defaults)
        store.update { settings in
            settings.hotkeyPreset = .commandShiftL
            settings.enableAnimations = false
            settings.hideOnResignActive = false
            settings.confirmBeforeResetLayout = false
        }

        let reloaded = LaunchpadSettingsStore(userDefaults: defaults)
        #expect(reloaded.current.hotkeyPreset == .commandShiftL)
        #expect(reloaded.current.enableAnimations == false)
        #expect(reloaded.current.hideOnResignActive == false)
        #expect(reloaded.current.confirmBeforeResetLayout == false)
    }

    @Test func settingsStorePostsChangeNotification() {
        let suiteName = "MacAppTests.Notification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(false)
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = LaunchpadSettingsStore(userDefaults: defaults)
        var didReceiveNotification = false

        let token = NotificationCenter.default.addObserver(
            forName: LaunchpadSettingsStore.didChangeNotification,
            object: store,
            queue: .main
        ) { _ in
            didReceiveNotification = true
        }

        store.update { settings in
            settings.enableAnimations.toggle()
        }

        NotificationCenter.default.removeObserver(token)
        #expect(didReceiveNotification)
    }

    @Test func editModeEntersOnOptionRisingEdge() {
        var state = EditModeStateMachine()

        let didEnter = state.handleOptionChanged(true)
        #expect(didEnter)
        #expect(state.isEditing)
        #expect(state.isOptionPressed)

        let repeatedPress = state.handleOptionChanged(true)
        #expect(repeatedPress == false)
    }

    @Test func exitingWhileHoldingOptionNeedsReleaseBeforeReentry() {
        var state = EditModeStateMachine()

        let optionEnter = state.handleOptionChanged(true)
        #expect(optionEnter)
        let didExit = state.exitEditingMode(userInitiated: true)
        #expect(didExit)
        #expect(state.isEditing == false)
        #expect(state.suppressOptionReenterEditing)

        let whileHeld = state.handleOptionChanged(true)
        #expect(whileHeld == false)
        #expect(state.isEditing == false)

        let didReleaseOption = state.handleOptionChanged(false)
        #expect(didReleaseOption == false)
        #expect(state.suppressOptionReenterEditing == false)

        let reenterAfterRelease = state.handleOptionChanged(true)
        #expect(reenterAfterRelease)
        #expect(state.isEditing)
    }

    @Test func exitingWithoutOptionDoesNotBlockNextOptionEntry() {
        var state = EditModeStateMachine()

        let enterViaLongPress = state.enterEditingMode(trigger: .longPress)
        #expect(enterViaLongPress)
        let didExit = state.exitEditingMode(userInitiated: true)
        #expect(didExit)
        #expect(state.suppressOptionReenterEditing == false)

        let optionEnter = state.handleOptionChanged(true)
        #expect(optionEnter)
        #expect(state.isEditing)
    }

    @Test func userInitiatedExitLeavesEditingMode() {
        var state = EditModeStateMachine()

        let didEnter = state.enterEditingMode(trigger: .longPress)
        #expect(didEnter)
        let didExit = state.exitEditingMode(userInitiated: true)
        #expect(didExit)
        #expect(state.isEditing == false)
    }
}
