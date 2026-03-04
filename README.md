# MacApp

一个基于 SwiftUI + AppKit 的 macOS 启动台（Launchpad）式覆盖层应用。
通过全局快捷键呼出，支持搜索、拖拽整理、文件夹管理与设置持久化。

## 功能

- 全局快捷键呼出/隐藏覆盖层（默认 `F4`，可改为 `⌥ Space` 或 `⌘⇧L`）
- 扫描应用目录并自动构建应用库：
  - `/Applications`
  - `/System/Applications`
  - `~/Applications`
- 支持搜索应用和文件夹
- 支持拖拽排序、拖拽创建文件夹、重命名文件夹
- 支持隐藏应用并持久化布局缓存
- 设置面板（动画开关、失焦自动隐藏、重建布局二次确认）

## 运行方式

### 使用 Xcode

1. 打开 `MacApp.xcodeproj`
2. 选择 `MacApp` Scheme
3. 运行（`Cmd + R`）

### 命令行构建

```bash
xcodebuild -project MacApp.xcodeproj -scheme MacApp -configuration Debug build
```

## 测试

```bash
xcodebuild -project MacApp.xcodeproj -scheme MacApp -destination 'platform=macOS' test
```

包含：

- 单元测试：`MacAppTests`
- UI 测试：`MacAppUITests`

## 数据与配置

- 用户设置通过 `UserDefaults` 持久化（热键、动画、失焦隐藏等）
- 布局缓存文件：
  `~/Library/Application Support/lancelot252.MacApp/launchpad-layout-cache.json`

## 项目结构

- `MacApp/`：主应用代码（UI、状态机、布局扫描与缓存）
- `MacAppTests/`：单元测试
- `MacAppUITests/`：UI 测试
- `MacApp.xcodeproj/`：Xcode 工程

