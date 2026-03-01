import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: LaunchpadSettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            LaunchpadSettingsForm(settingsStore: settingsStore)
                .frame(maxWidth: 420)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("说明")
                    .font(.headline)
                Text("当前应用为 Agent 模式（无 Dock 图标）。")
                Text("快捷键可能与系统设置冲突，建议优先检查系统键盘快捷键。")
                Text("设置保存后立即生效。")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 360)
    }
}

struct LaunchpadSettingsForm: View {
    @ObservedObject var settingsStore: LaunchpadSettingsStore
    var showOpenSystemSettingsButton: Bool = false
    var onOpenSystemSettings: (() -> Void)?

    var body: some View {
        Form {
            Section("快捷键") {
                Picker("唤起热键", selection: hotkeyBinding) {
                    ForEach(LaunchpadHotkeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("行为") {
                Toggle("启用显示/隐藏动画", isOn: animationBinding)
                Toggle("失去焦点时自动隐藏", isOn: hideOnResignBinding)
                Toggle("重建布局前二次确认", isOn: confirmResetBinding)
            }

            if showOpenSystemSettingsButton, let onOpenSystemSettings {
                Section("系统") {
                    Button("打开系统设置窗口") {
                        onOpenSystemSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyBinding: Binding<LaunchpadHotkeyPreset> {
        Binding(
            get: { settingsStore.current.hotkeyPreset },
            set: { newPreset in
                settingsStore.update { settings in
                    settings.hotkeyPreset = newPreset
                }
            }
        )
    }

    private var animationBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.current.enableAnimations },
            set: { newValue in
                settingsStore.update { settings in
                    settings.enableAnimations = newValue
                }
            }
        )
    }

    private var hideOnResignBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.current.hideOnResignActive },
            set: { newValue in
                settingsStore.update { settings in
                    settings.hideOnResignActive = newValue
                }
            }
        )
    }

    private var confirmResetBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.current.confirmBeforeResetLayout },
            set: { newValue in
                settingsStore.update { settings in
                    settings.confirmBeforeResetLayout = newValue
                }
            }
        )
    }
}

struct InlineSettingsPanel: View {
    @ObservedObject var settingsStore: LaunchpadSettingsStore
    let onOpenSystemSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.headline)

            LaunchpadSettingsForm(
                settingsStore: settingsStore,
                showOpenSystemSettingsButton: true,
                onOpenSystemSettings: onOpenSystemSettings
            )
        }
        .padding(12)
        .frame(width: 360)
    }
}
