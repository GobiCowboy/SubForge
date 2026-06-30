import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private weak var model: AppModel?

    override init() {
        super.init()

        statusItem.button?.image = MenuBarIconFactory.makeImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "SubForge"
        statusItem.isVisible = false

        menu.delegate = self
        statusItem.menu = menu
    }

    func bind(model: AppModel) {
        self.model = model
        rebuildMenu()
    }

    func setVisible(_ isVisible: Bool) {
        statusItem.isVisible = isVisible
    }

    func refreshMenu() {
        rebuildMenu()
    }

    func invalidate() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            self.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        addItem("显示 SubForge", action: #selector(showMainWindow), systemImage: "macwindow")
        addItem("导入文件...", action: #selector(importFile), systemImage: "square.and.arrow.down")

        menu.addItem(.separator())

        if model?.isWatchingDirectory == true {
            addItem("停止监听", action: #selector(toggleWatchFolder), systemImage: "stop.circle")
        } else {
            addItem(
                "开始监听",
                action: #selector(toggleWatchFolder),
                systemImage: "play.circle",
                isEnabled: canStartWatching
            )
        }

        addItem(
            "导出",
            action: #selector(exportArtifacts),
            keyEquivalent: "e",
            modifiers: [.command],
            systemImage: "square.and.arrow.up",
            isEnabled: model?.canExport == true
        )

        menu.addItem(.separator())

        addItem("设置...", action: #selector(openSettings), systemImage: "gearshape")
        addItem("退出 SubForge", action: #selector(quit), systemImage: "power")
    }

    private var canStartWatching: Bool {
        guard let model else { return false }
        return !model.settings.watchSettings.directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    private func addItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        systemImage: String? = nil,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = isEnabled
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        }
        menu.addItem(item)
        return item
    }

    @objc private func showMainWindow() {
        model?.activateMainWindow()
    }

    @objc private func importFile() {
        model?.activateMainWindow()
        model?.requestImportFromMenu()
    }

    @objc private func toggleWatchFolder() {
        if model?.isWatchingDirectory == true {
            model?.stopWatchFolder()
        } else {
            model?.startWatchFolder()
        }
        rebuildMenu()
    }

    @objc private func exportArtifacts() {
        model?.activateMainWindow()
        model?.exportArtifacts()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
