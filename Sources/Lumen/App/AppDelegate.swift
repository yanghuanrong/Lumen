import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = SettingsStore()
    private lazy var translator = Translator(settings: settings)
    private lazy var viewModel = TranslationViewModel(translator: translator, settings: settings)

    private let hotKeyManager = GlobalHotKeyManager()
    private var panelController: FloatingPanelController!
    private var settingsWindow: NSWindow!
    private var statusItem: NSStatusItem?

    private var cancellables = Set<AnyCancellable>()
    private var blurObservers: [NSObjectProtocol] = []

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildSettingsWindow()
        observePanelBlur()
        registerHotKey()
        observeSettings()
        updateStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
        for observer in blurObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        blurObservers.removeAll()
    }

    /// 点击 Dock/重复启动时呼出面板（.accessory 策略下一般不会触发）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        togglePanel()
        return true
    }

    // MARK: - 面板

    /// 演示模式：跳过剪贴板，直接填入指定文本并翻译。
    /// 用于快速验证 UI 渲染与翻译链路是否正常。
    func demoShow(text: String) {
        panelController.show()
        viewModel.demoTranslate(text)
    }

    private func buildPanel() {
        panelController = FloatingPanelController(settings: settings)
        panelController.buildPanel()

        let view = TranslationPanelView(
            viewModel: viewModel,
            settings: settings,
            onClose: { [weak self] in self?.hidePanel() },
            onOpenSettings: { [weak self] in self?.showSettings() },
            onHideRequest: { [weak self] in self?.hidePanel() }
        )
        panelController.setContentView(view)
    }

    /// 面板失焦 / 切到其它 App 时按设置隐藏翻译窗
    private func observePanelBlur() {
        let resign = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panelController.panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleHideOnBlur()
            }
        }

        let switchApp = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let other = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let other, other.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return
            }
            Task { @MainActor in
                self?.hidePanelOnBlurIfNeeded()
            }
        }

        blurObservers = [resign, switchApp]
    }

    /// resignKey 后稍等，避免打开设置窗时抢焦点误关
    private func scheduleHideOnBlur() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            hidePanelOnBlurIfNeeded()
        }
    }

    private func hidePanelOnBlurIfNeeded() {
        guard settings.hideOnBlur, panelController.isVisible else { return }
        // 设置窗正在前台交互时不算离开本应用
        if settingsWindow.isVisible, settingsWindow.isKeyWindow { return }
        if panelController.panel.isKeyWindow { return }
        hidePanel()
    }

    private func togglePanel() {
        if panelController.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        viewModel.onHotkeyTriggered()
        panelController.show()
    }

    private func hidePanel() {
        viewModel.onHide()
        panelController.hide()
    }

    // MARK: - 设置窗口

    private func buildSettingsWindow() {
        let view = SettingsView(
            settings: settings,
            onHotKeyChanged: { [weak self] key in
                self?.registerHotKey(custom: key)
            },
            onClose: { [weak self] in
                self?.settingsWindow.close()
            }
        )

        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Lumen 设置"
        settingsWindow.contentView = NSHostingView(rootView: AnyView(view))
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.titleVisibility = .hidden
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.center()
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    // MARK: - 快捷键

    private func registerHotKey() {
        let ok = hotKeyManager.register(settings.hotKey) { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
        if !ok {
            presentHotKeyConflictAlert()
        }
    }

    private func registerHotKey(custom: HotKey) {
        let ok = hotKeyManager.register(custom) { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
        if !ok {
            presentHotKeyConflictAlert()
        }
    }

    private func presentHotKeyConflictAlert() {
        let alert = NSAlert()
        alert.messageText = "快捷键注册失败"
        alert.informativeText = "「\(settings.hotKey.displayString)」可能已被其它应用占用。请在设置中换一个组合键。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            showSettings()
        }
    }

    // MARK: - 设置联动

    private func observeSettings() {
        settings.$hotKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] key in
                guard let self else { return }
                self.registerHotKey(custom: key)
            }
            .store(in: &cancellables)

        settings.$showMenuBarItem
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 菜单栏

    private func updateStatusItem() {
        if settings.showMenuBarItem {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(
                systemSymbolName: "character.book.closed",
                accessibilityDescription: "Lumen"
            )
            item.button?.image?.isTemplate = true
            item.menu = buildStatusMenu()
            statusItem = item
        } else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "打开翻译面板", action: #selector(statusOpenPanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let clipboardItem = NSMenuItem(title: "翻译剪贴板内容", action: #selector(statusTranslateClipboard), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(statusOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出 Lumen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    @objc private func statusOpenPanel() {
        togglePanel()
    }

    @objc private func statusTranslateClipboard() {
        viewModel.clear()
        viewModel.onHotkeyTriggered()
        panelController.show()
    }

    @objc private func statusOpenSettings() {
        showSettings()
    }
}