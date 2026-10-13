# Lumen

一个用 SwiftUI + AppKit 编写的 macOS 划词翻译工具，独立项目。

只聚焦一个核心场景：

> **按快捷键呼出 → 粘贴 → 自动翻译**，中英双向。

## 特性

- **全局快捷键呼出**，默认 `⌥D`，可在设置里自定义（基于 Carbon EventHotKey，**无需辅助功能授权**）
- **自动读取剪贴板**，呼出即填入，直接出结果
- **方向自动识别**，中文→英文 / 英文→中文，不用手动切换
- **单词模式给完整词典信息**：音标、分词性释义、例句、词形变化
- **多引擎自动降级**：单词走词典引擎，整句走翻译引擎，失败自动切换下一个
- **不污染剪贴板**：默认不自动复制，需要时手动点「复制译文」
- 无 Dock 图标，只在菜单栏和浮动面板出现

## 快速开始

```bash
./build.sh            # 编译 + 打包成 build/Lumen.app
open build/Lumen.app  # 启动
```

安装到应用程序：

```bash
cp -R build/Lumen.app /Applications/
```

开发模式运行：

```bash
swift run Lumen       # 注意某些环境需要 --disable-sandbox
```

## 项目位置

```
<工作区>/learn/Lumen
```

| 路径 | 说明 |
|---|---|
| `learn/Lumen/` | **项目根目录** |
| `learn/Lumen/Lumen.xcodeproj` | Xcode 工程（调试用） |
| `learn/Lumen/Sources/Lumen/` | 全部 Swift 源码 |
| `learn/Lumen/build/Lumen.app` | 打包产物（可直接运行） |
| `learn/Lumen/scripts/generate_xcodeproj.rb` | 工程生成脚本 |
| `project/other/pot-desktop` | 第三方参考项目，与本项目无关 |

快速打开：

```bash
open ~/WorkBuddy/2026-10-13-11-30-20/learn/Lumen/Lumen.xcodeproj
```

## 调试

**可以调试，工程已经生成好了。** 之前只有 `Package.swift` 时确实无法在 Xcode 里断点调试，现在补上了 `.xcodeproj`。

### 用 Xcode 调试（推荐）

```bash
open Lumen.xcodeproj
```

已配置好的便利点：

- **Debug 构建启动即自动呼出面板**，不用每次手动按 `⌥D`，可以直接下断点
- 想换测试文本：Scheme → Run → Arguments 里加环境变量 `LUMEN_DEMO_TEXT=你好`
- 想安静调试（不自动弹面板）：加环境变量 `LUMEN_NO_AUTO_SHOW=1`
- `LSUIElement` 已配好，调试时也是无 Dock 图标的行为

常用断点位置：

| 想查什么 | 断点位置 |
|---|---|
| 翻译为什么选了这个引擎 | `Translator.swift` → `engineChain(for:)` |
| 某个引擎返回解析错了 | `YoudaoEngine.swift` → `translate(_:from:to:)` |
| 网络请求是否发出 | `HTTPClient.swift` → `send(_:timeout:retries:decode:)` |
| 热键有没有触发 | `GlobalHotKeyManager.swift` → `register(_:onTrigger:)` |
| 快捷键显示是否正确 | `SettingsStore.swift` → `HotKey.displayString` |

### 命令行调试（不开 Xcode）

```bash
# Debug 构建
swift build --disable-sandbox --configuration debug

# 带自检
./.build/debug/Lumen --selftest

# 带渲染（看界面）
./.build/debug/Lumen --render "serendipity" /tmp/word.png

# 跳过剪贴板直接呼出面板
./.build/debug/Lumen --demo "hello"
```

### 重新生成 Xcode 工程

改了文件结构（增删源文件、改 bundle id）后需要重跑：

```bash
ruby scripts/generate_xcodeproj.rb
```

> 依赖 Ruby 的 `xcodeproj` gem：`gem install xcodeproj --no-document`

## 如何验证它真的能用

编译通过 ≠ 功能正常。下面几条覆盖从底层到界面的完整链路，**都不需要你手动按快捷键**。

### 1. 命令行自检（最快，5 秒）

```bash
./build.sh && ./.build/release/Lumen --selftest
```

覆盖语言识别、单词判定、键码映射、修饰键往返、各引擎连通性、自动调度链路。24 项全 `✓` 即为正常。

### 2. 渲染面板截图（验证 UI 与翻译真实可用）

```bash
./.build/release/Lumen --render "serendipity" /tmp/word.png
./.build/release/Lumen --render "今天天气不错" /tmp/sentence.png
./.build/release/Lumen --render-settings          # 设置页
```

这三个命令会**真实发起网络请求**并把面板渲染成 PNG。用来在不依赖屏幕录制权限的前提下确认界面能画出来、翻译结果能填充。

### 3. 交互验证（真实使用路径）

```bash
open build/Lumen.app
```

然后：

1. 菜单栏出现书本图标 → 说明以 `LSUIElement` 正常启动
2. 在任意 App 里复制一个单词（比如浏览器里选中复制）
3. 按 `⌥D` → 面板应自动填入剪贴板内容并立刻出结果
4. 按 `⌘⇧C` 复制译文，粘贴到任意地方验证
5. `Esc` 关闭

换别的词重复第 2–3 步，确认中英双向都正常。

### 4. 单独验证热键注册

```bash
./.build/release/Lumen --demo "hello"
```

跳过剪贴板直接呼出面板填入指定文本，适合排查"是不是热键没注册上"这类问题。

### 常见问题

| 现象 | 原因与处理 |
|---|---|
| 打不开，提示"无法验证开发者" | 未签名公证。右键选「打开」，或 `xattr -d com.apple.quarantine /Applications/Lumen.app` |
| 按 `⌥D` 没反应 | 快捷键被其它 App 占用。面板里的齿轮图标 → 设置 → 点快捷键框重新录制 |
| 面板弹不出但菜单栏有图标 | 菜单栏 → 「打开翻译面板」手动打开；若也不响应，说明热键被占 |
| 面板能开但翻译失败 | 看面板底部状态栏显示的引擎名；MyMemory 有每日额度，用多了会失败 |
| 粘贴没反应 | 面板必须是可键窗口；若输入框无光标说明焦点丢了，点一下输入框 |

## 翻译引擎

引擎可在设置里切换。默认「自动」模式会按输入类型智能选路并自动降级。

| 引擎 | 密钥 | 适用 | 说明 |
|---|---|---|---|
| **有道词典** | 不需要 | 单词、短语 | 释义/音标/例句齐全，国内直连 |
| **MyMemory** | 不需要 | 整句、段落 | 长文本稳定，免费额度约 5000 词/天 |
| **OpenAI 兼容** | 可选 | 高质量翻译 | 自定义地址，兼容 DeepSeek / 智谱 / Ollama / one-api 等 |

**关于自动模式的路由逻辑**：单词 → 有道（拿词典信息），整句 → MyMemory；任一失败会自动尝试下一个引擎。

配置 OpenAI 兼容服务时填三个字段：接口地址（如 `https://api.deepseek.com/v1`）、模型名、API Key。本地 Ollama 的 Key 可留空。

## 键盘操作

| 操作 | 快捷键 |
|---|---|
| 呼出/隐藏面板 | `⌥D`（可改） |
| 翻译 | `↵` |
| 复制译文 | `⌘⇧C` |
| 清空 | `Esc` |

## 项目结构

```
Lumen/
├── Package.swift
├── build.sh                      # 编译 + 打包 .app + 生成图标 + ad-hoc 签名
└── Sources/Lumen/
    ├── main.swift                # 入口（LSUIElement，无 Dock 图标）
    ├── App/
    │   ├── AppDelegate.swift     # 生命周期、热键注册、面板与设置窗口
    │   └── SelfTest.swift        # --selftest 命令行自检
    ├── Core/
    │   ├── Language.swift        # 中英双向语言判定 + 单词识别
    │   ├── HTTPClient.swift      # 统一 UA / 超时 / 重试 / 错误处理
    │   ├── Models.swift          # 翻译结果、释义、例句等模型
    │   ├── ClipboardService.swift# 带快照的剪贴板封装
    │   └── SettingsStore.swift   # UserDefaults 持久化
    ├── Translate/
    │   ├── TranslationEngine.swift   # 引擎协议
    │   ├── YoudaoEngine.swift        # 有道：词典 + 音标 + 例句
    │   ├── MyMemoryEngine.swift      # 整句翻译，含长文本分块
    │   ├── OpenAICompatibleEngine.swift
    │   └── Translator.swift      # 调度：选路、降级、缓存
    ├── HotKey/
    │   └── GlobalHotKeyManager.swift  # Carbon EventHotKey
    ├── Window/
    │   └── FloatingPanel.swift   # NSPanel 悬浮面板
    ├── ViewModels/
    │   └── TranslationViewModel.swift
    └── Views/
        ├── TranslationPanelView.swift
        ├── SettingsView.swift
        ├── HotKeyRecorder.swift
        └── WindowDragArea.swift
```

## 实现要点

**全局快捷键用Carbon 而非 `NSEvent.addGlobalMonitor`。** 后者要求辅助功能授权，系统会弹权限请求；Carbon `RegisterEventHotKey` 不需要任何授权就能注册系统级快捷键，稳定性也更好。代价是拿不到回调事件对象，但对「按下就触发」的场景够用。

**面板用 `NSPanel` 且重写 `canBecomeKey`。** 默认 `NSPanel` 的 `canBecomeKey` 为 false，SwiftUI 里的 `TextField` 拿不到焦点，粘贴就没法工作。同时隐藏了系统关闭按钮，避免误触把面板关掉。

**单词与句子走不同引擎。** 词典引擎对长句会直接返回空（实测有道对整句只返回 web 摘要甚至空对象），所以必须靠 `LanguageDetector.looksLikeSingleWord` 分流，这也是自检里第 3 项会看到有道「整句」失败的原因——这是预期行为，实际由 MyMemory 兜住。

**剪贴板默认不写。** 划词翻译高频使用，自动改剪贴板很容易破坏用户原本复制的内容。默认只读，写入需要显式点击；即使开了「翻译后自动复制」，关闭面板时也会用 `changeCount` 判断是否还原。

## 已知限制

- **只支持中英双向**，这是刻意收窄的范围。
- 免密钥引擎（MyMemory）有 IP 级日额度，重度使用建议配置 OpenAI 兼容服务。
- 有道、MyMemory 都是网页端公开接口，**不保证长期可用**。这是免密钥方案的固有代价，一旦某天失效，只需在该引擎文件里换掉请求地址，调度层不用改。
- 尚未做代码签名公证（notarization），首次打开可能需要在「系统设置 → 隐私与安全性」点「仍要打开」，或对 app 执行 `xattr -d com.apple.quarantine Lumen.app`。

## 后续可做

- 剪贴板监听模式（复制即翻译）
- 划词取词（不呼出面板，直接翻译选中文字）
- TTS 朗读
- 释义来源多样化（接入 dictionaryapi.dev 补英文例句）