import AppKit
import Foundation
import MacBastionCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = ConfigStore()
    private let runtime = TunnelRuntime()
    private var loadedConfig: LoadedConfig?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.title = "MB"
        statusItem.button?.toolTip = "Mac Bastion"
        reload()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func reload() {
        do {
            loadedConfig = try store.load()
        } catch {
            loadedConfig = nil
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Mac Bastion", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        guard let loadedConfig else {
            let missing = NSMenuItem(title: "No config found", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
            menu.addItem(NSMenuItem(title: "Create Sample Config", action: #selector(createSampleConfig), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Import Config...", action: #selector(importConfig), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
            statusItem.button?.title = "MB"
            statusItem.menu = menu
            return
        }

        let statuses = runtime.statuses(for: loadedConfig.config.profiles)
        let runningCount = statuses.filter { $0.state == .running }.count
        let issues = ConfigValidator.validate(loadedConfig.config, checkLivePorts: false)
        let errorCount = issues.filter { $0.severity == .error }.count
        statusItem.button?.title = runningCount > 0 ? "MB \(runningCount)" : "MB"

        let summary = NSMenuItem(
            title: "\(runningCount)/\(loadedConfig.config.profiles.count) running" + (errorCount > 0 ? " - \(errorCount) config error(s)" : ""),
            action: nil,
            keyEquivalent: ""
        )
        summary.isEnabled = false
        menu.addItem(summary)

        if !issues.isEmpty {
            let issueMenu = NSMenuItem(title: "Validation Issues", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for issue in issues.prefix(8) {
                let item = NSMenuItem(title: issue.description, action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
            }
            issueMenu.submenu = submenu
            menu.addItem(issueMenu)
        }

        menu.addItem(.separator())

        for profile in loadedConfig.config.profiles {
            let status = runtime.status(for: profile)
            let item = NSMenuItem(title: "\(profile.name) - \(status.state.rawValue)", action: nil, keyEquivalent: "")
            item.submenu = profileMenu(profile: profile, status: status)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Start All", action: #selector(startAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop All", action: #selector(stopAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Validate Config", action: #selector(validateConfig), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Import Config...", action: #selector(importConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Export Config...", action: #selector(exportConfig), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func profileMenu(profile: BastionProfile, status: TunnelStatus) -> NSMenu {
        let menu = NSMenu()

        for forward in profile.forwards {
            let item = NSMenuItem(
                title: "\(forward.name): \(forward.local.host):\(forward.local.port) -> \(forward.remote.host):\(forward.remote.port)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        switch status.state {
        case .running:
            menu.addItem(actionItem("Stop", action: #selector(stopProfile(_:)), profileName: profile.name))
            menu.addItem(actionItem("Restart", action: #selector(restartProfile(_:)), profileName: profile.name))
        case .stopped, .stale, .failed:
            menu.addItem(actionItem("Start", action: #selector(startProfile(_:)), profileName: profile.name))
            if status.state == .stale {
                menu.addItem(actionItem("Clear Stale State", action: #selector(stopProfile(_:)), profileName: profile.name))
            }
        }

        menu.addItem(actionItem("Copy SSH Command", action: #selector(copySSHCommand(_:)), profileName: profile.name))
        menu.addItem(actionItem("Copy Last Log", action: #selector(copyLastLog(_:)), profileName: profile.name))

        return menu
    }

    private func actionItem(_ title: String, action: Selector, profileName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = profileName
        return item
    }

    private func profile(named name: String) -> BastionProfile? {
        loadedConfig?.config.profiles.first { $0.name == name }
    }

    @objc private func startProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let profile = profile(named: name) else {
            return
        }
        do {
            _ = try runtime.start(profile)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    @objc private func stopProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else {
            return
        }
        do {
            _ = try runtime.stop(profileName: name)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    @objc private func restartProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let profile = profile(named: name) else {
            return
        }
        do {
            _ = try runtime.restart(profile)
            rebuildMenu()
        } catch {
            showError(error)
        }
    }

    @objc private func copySSHCommand(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let profile = profile(named: name) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SSHCommandBuilder.command(for: profile).rendered, forType: .string)
    }

    @objc private func copyLastLog(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(runtime.tailLog(for: name), forType: .string)
    }

    @objc private func startAll() {
        guard let profiles = loadedConfig?.config.profiles else {
            return
        }
        for profile in profiles where profile.enabled {
            do {
                _ = try runtime.start(profile)
            } catch {
                showError(error)
                break
            }
        }
        rebuildMenu()
    }

    @objc private func stopAll() {
        runtime.stopAll(knownProfileNames: loadedConfig?.config.profiles.map { $0.name } ?? [])
        rebuildMenu()
    }

    @objc private func reloadConfig() {
        reload()
    }

    @objc private func validateConfig() {
        guard let config = loadedConfig?.config else {
            showMessage("No config loaded.")
            return
        }
        let issues = ConfigValidator.validate(config, checkLivePorts: true)
        if issues.isEmpty {
            showMessage("Config is valid.")
        } else {
            showMessage(issues.map(\.description).joined(separator: "\n"))
        }
    }

    @objc private func openConfig() {
        let url = loadedConfig?.rootURL ?? store.defaultConfigURL
        NSWorkspace.shared.open(url)
    }

    @objc private func createSampleConfig() {
        do {
            _ = try store.ensureSampleConfig(force: false)
            reload()
        } catch {
            showError(error)
        }
    }

    @objc private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .text]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else {
            return
        }
        do {
            try store.importConfig(from: source, into: store.defaultConfigURL, mode: .merge)
            reload()
        } catch {
            showError(error)
        }
    }

    @objc private func exportConfig() {
        guard let config = loadedConfig?.config else {
            showMessage("No config loaded.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.yaml]
        panel.nameFieldStringValue = "mac-bastion-config.yaml"
        guard panel.runModal() == .OK, let output = panel.url else {
            return
        }
        do {
            try store.exportYAML(config: config).write(to: output, atomically: true, encoding: .utf8)
        } catch {
            showError(error)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ error: Error) {
        showMessage(String(describing: error))
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Mac Bastion"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension UTType {
    static var yaml: UTType {
        UTType(filenameExtension: "yaml") ?? .text
    }
}

@main
struct MacBastionMenuMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
