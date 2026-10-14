# Lumen

macOS 划词翻译小工具：快捷键呼出 → 读剪贴板 → 中英互译。SwiftUI + AppKit，无 Dock 图标。

---

## For AI agents

本仓库的主要读者是 AI。改代码前先读本节；人类使用说明见文末。

### Goal

只做一件事：**全局快捷键呼出悬浮面板，粘贴/自动填入中英文，给出翻译（单词要有词典级信息）**。不要扩成全能翻译器。

### Hard constraints

- 只支持中英双向；不要加其它语种 UI/路由。
- 不引入新依赖（含 SPM），除非用户明确同意。
- 最小改动；不做顺手重构。
- **禁止直推 `main`**：开 `feature/*` / `fix/*` / `docs/*` 分支 → PR → 等 CI / CodeRabbit → 再合并。
- 钱/权限/支付相关：本项目没有；全局快捷键用 Carbon，**不要**改成需要辅助功能授权的方案。

### Layout (edit here)

```
Sources/Lumen/
  main.swift                 # 入口；--selftest / --render / --demo
  App/AppDelegate.swift      # 生命周期、热键、面板显隐（含失焦隐藏）
  App/SelfTest.swift         # 命令行自检
  App/PanelRenderer.swift    # 离屏渲染 PNG
  ViewModels/TranslationViewModel.swift  # 呼出→翻译→复制；须转发 translator 变更
  Translate/Translator.swift # 选路、降级、缓存
  Translate/YoudaoEngine.swift / GoogleEngine.swift / MyMemoryEngine.swift
  HotKey/GlobalHotKeyManager.swift
  Window/FloatingPanel.swift
  Views/TranslationPanelView.swift / SettingsView.swift
  Core/SettingsStore.swift / Language.swift / HTTPClient.swift / ClipboardService.swift
```

构建与工程：`Package.swift`、`build.sh`；Xcode 工程由 `scripts/generate_xcodeproj.rb` 生成（已 gitignore）。

### Behavior notes (easy to break)

- UI 只观察 `TranslationViewModel`：`translator` 的 `@Published` 必须转发到 viewModel，否则会卡在「翻译中…」。
- 单词走有道、整句走谷歌（`auto`）；失败降级 MyMemory/有道；有道整句失败是预期，由降级兜住。
- 面板失焦 / 切到其它 App 时按 `hideOnBlur` 隐藏（默认开）。
- 默认不自动写剪贴板；开启「自动复制」后译文会留在剪贴板（不做还原）。
- 快捷键录制禁止裸 ⌘+字母/数字（会全局抢占其它 App 菜单快捷键）与单独 ⇧。
- 开机自启用 `SMAppService`（macOS 13+）；启动时以系统登录项实际状态为准修正设置。

### Verify before claiming done

```bash
swift build
swift run Lumen --selftest          # 引擎与调度；应几乎全 ✓
swift run Lumen --render "serendipity" /tmp/lumen-word.png
./build.sh debug && open build/Lumen.app
```

交互抽查：`⌥D`（可改）呼出 → 出结果 → 点其它 App 面板应收起。

### Do not

- 不要把 pot-desktop / Tauri 方案搬进来；本项目是原生 Swift。
- 不要提交 `.build/`、`build/`、`Lumen.xcodeproj/`、`xcuserdata`。
- 不要在 README 里堆长篇「如何用 Xcode 下断点」——那些信息应落在代码注释或 PR 里，需要时再搜源码。

---

## 使用说明

### 安装运行

```bash
./build.sh
open build/Lumen.app
# 可选：cp -R build/Lumen.app /Applications/
```

首次打开若被拦截：右键 → 打开，或  
`xattr -d com.apple.quarantine /Applications/Lumen.app`

### 日常使用

| 操作 | 说明 |
|------|------|
| 呼出 / 隐藏 | 默认 `⌥D`，设置里可改 |
| 自动填入 | 默认读取剪贴板并翻译 |
| 回车 | 再译一次 |
| 复制译文 | 面板按钮（可在设置开「自动复制」） |
| Esc / 失焦 | 隐藏面板 |
| 菜单栏书本图标 | 打开面板、设置、退出 |
| 开机自启 | 设置 → 行为 → 开机自动启动 |

设置（齿轮）：引擎（自动 / 有道 / 谷歌 / MyMemory）、快捷键、失焦隐藏等。

### 常见问题

| 现象 | 处理 |
|------|------|
| 快捷键无反应 | 设置里重新录制；可能被其它 App 占用 |
| 一直「翻译中…」 | 多为 UI 未刷新或网络失败；跑 `--selftest` 看引擎 |
| MyMemory 失败 | 免费额度用尽；换引擎 |
| 谷歌引擎失败/慢 | 非官方接口，国内需系统代理；无代理时建议切其它引擎 |
| 有道释义/音标缺失 | 网页端接口临时改版或限流；译文不受影响（自动走谷歌/MyMemory） |
