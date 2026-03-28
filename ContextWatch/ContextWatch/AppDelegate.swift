import Cocoa
import UserNotifications
import Sparkle

/// Délégué principal de l'application.
/// Gère le status item dans la menu bar, le menu contextuel,
/// et orchestre le SessionMonitor + NotificationManager.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Composants

    private var statusItem: NSStatusItem!
    private let sessionMonitor = SessionMonitor()
    private let notificationManager = NotificationManager()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    // MARK: - Cycle de vie

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemTitle(sessions: [])
        buildMenu(sessions: [])

        notificationManager.requestPermission()

        sessionMonitor.onUpdate = { [weak self] sessions in
            self?.handleUpdate(sessions: sessions)
        }

        sessionMonitor.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionMonitor.stopMonitoring()
    }

    // MARK: - Mise à jour

    private func handleUpdate(sessions: [SessionInfo]) {
        updateStatusItemTitle(sessions: sessions)
        buildMenu(sessions: sessions)
        notificationManager.evaluate(sessions: sessions)
    }

    /// Affiche la session la plus critique dans la menu bar avec couleur
    private func updateStatusItemTitle(sessions: [SessionInfo]) {
        guard let button = statusItem.button else { return }

        guard let worst = sessions.max(by: { $0.percentage < $1.percentage }) else {
            button.attributedTitle = NSAttributedString(
                string: "◯ —",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
            return
        }

        let text = "\(worst.activity.icon) \(worst.percentage)%"
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: colorForPercentage(worst.percentage)]
        )
    }

    /// Couleur selon le niveau : vert → jaune → orange → rouge
    private func colorForPercentage(_ pct: Int) -> NSColor {
        switch pct {
        case 0...60:
            return NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1.0) // Vert
        case 61...79:
            return NSColor(red: 0.95, green: 0.77, blue: 0.06, alpha: 1.0) // Jaune
        case 80...89:
            return NSColor(red: 0.96, green: 0.55, blue: 0.18, alpha: 1.0) // Orange
        default:
            return NSColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1.0) // Rouge
        }
    }

    /// Couleur du nom de projet selon son préfixe/catégorie
    private func colorForProject(_ name: String) -> NSColor {
        let lower = name.lowercased()
        if lower.hasPrefix("app ") {
            return NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0)   // Bleu ciel
        } else if lower.hasPrefix("site ") {
            return NSColor(red: 0.65, green: 0.90, blue: 0.65, alpha: 1.0)  // Vert menthe
        } else if lower.hasPrefix("crm") || lower.contains("crm") {
            return NSColor(red: 1.0, green: 0.75, blue: 0.45, alpha: 1.0)   // Orange doux
        } else if lower.hasPrefix("screenshot") || lower.hasPrefix("screen") {
            return NSColor(red: 0.85, green: 0.70, blue: 1.0, alpha: 1.0)   // Violet clair
        } else if lower.hasPrefix("api") || lower.hasPrefix("server") || lower.hasPrefix("backend") {
            return NSColor(red: 1.0, green: 0.60, blue: 0.65, alpha: 1.0)   // Rose
        } else {
            return NSColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0)  // Blanc lumineux (fallback)
        }
    }

    // MARK: - Menu

    private func buildMenu(sessions: [SessionInfo]) {
        let menu = NSMenu()

        if sessions.isEmpty {
            let noSession = NSMenuItem(title: "Aucune session active", action: nil, keyEquivalent: "")
            noSession.isEnabled = false
            menu.addItem(noSession)
        } else {
            // En-tête avec décompte par état
            let workingCount = sessions.filter { $0.activity == .working }.count
            let waitingCount = sessions.filter { $0.activity == .waiting }.count
            let headerText: String
            if sessions.count == 1 {
                headerText = "1 session"
            } else {
                headerText = "\(sessions.count) sessions"
            }
            var statusParts: [String] = []
            if workingCount > 0 { statusParts.append("⚡\(workingCount)") }
            if waitingCount > 0 { statusParts.append("💬\(waitingCount)") }
            let headerFull = statusParts.isEmpty
                ? headerText
                : "\(headerText)  —  \(statusParts.joined(separator: "  "))"
            let header = NSMenuItem(title: headerFull, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            // Tri : activité d'abord (working > waiting > idle), puis date décroissante
            let sorted = sessions.sorted { a, b in
                let priorityA = a.activity == .working ? 0 : (a.activity == .waiting ? 1 : 2)
                let priorityB = b.activity == .working ? 0 : (b.activity == .waiting ? 1 : 2)
                if priorityA != priorityB { return priorityA < priorityB }
                return a.modificationDate > b.modificationDate
            }
            for session in sorted {
                addSessionItems(to: menu, session: session)
            }
        }

        // Dernière mise à jour
        menu.addItem(.separator())
        let timeStr: String
        if let lastUpdate = sessionMonitor.lastUpdate {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            timeStr = fmt.string(from: lastUpdate)
        } else {
            timeStr = "—"
        }
        let updateItem = NSMenuItem(
            title: "Dernière mise à jour : \(timeStr)",
            action: nil, keyEquivalent: ""
        )
        updateItem.isEnabled = false
        menu.addItem(updateItem)

        // Actions
        menu.addItem(.separator())
        let openItem = NSMenuItem(
            title: "Ouvrir ~/.claude/projects/",
            action: #selector(openProjectsFolder),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        // Mise à jour
        let sparkleItem = NSMenuItem(
            title: "Vérifier les mises à jour…",
            action: #selector(checkForUpdates),
            keyEquivalent: "u"
        )
        sparkleItem.target = self
        menu.addItem(sparkleItem)

        // Version
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionItem = NSMenuItem(
            title: "ContextWatch v\(version) (\(build))",
            action: nil, keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quitter",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Ajoute les items de menu pour une session, avec code couleur sélectif
    private func addSessionItems(to menu: NSMenu, session: SessionInfo) {
        // Action = ouvrir Claude Desktop et tenter de focus la bonne session
        let item = NSMenuItem(title: "", action: #selector(openSession(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = session.cwd

        let font = NSFont.menuFont(ofSize: 13)
        let boldFont = NSFont.boldSystemFont(ofSize: 13)
        let smallFont = NSFont.menuFont(ofSize: 11)
        let color = colorForPercentage(session.percentage)

        let str = NSMutableAttributedString()

        // Icône d'activité (⚡ working, 💬 waiting, 💤 idle)
        str.append(NSAttributedString(string: "\(session.activity.icon) ", attributes: [
            .font: font
        ]))

        // Nom du projet — couleur selon la catégorie
        str.append(NSAttributedString(string: session.displayName, attributes: [
            .foregroundColor: colorForProject(session.displayName), .font: boldFont
        ]))

        // Séparateur
        str.append(NSAttributedString(string: "  —  ", attributes: [
            .foregroundColor: NSColor(white: 0.55, alpha: 1.0), .font: font
        ]))

        // Pourcentage en couleur + gras
        str.append(NSAttributedString(string: "\(session.percentage)%", attributes: [
            .foregroundColor: color, .font: boldFont
        ]))

        // Tokens — gris clair, lisible
        str.append(NSAttributedString(string: "  (\(session.inputTokensFormatted) / \(session.maxTokensFormatted))", attributes: [
            .foregroundColor: NSColor(white: 0.60, alpha: 1.0), .font: smallFont
        ]))

        // Modèle — gris moyen
        str.append(NSAttributedString(string: "  \(session.modelShortName)", attributes: [
            .foregroundColor: NSColor(white: 0.50, alpha: 1.0), .font: smallFont
        ]))

        // Badge Computer Use
        if session.usesComputerUse {
            str.append(NSAttributedString(string: "  🖥️", attributes: [.font: smallFont]))
        }

        item.attributedTitle = str
        menu.addItem(item)

        // Alternate (Option) : détails techniques pour calibration
        let altTitle = "   ↳ \(session.inputTokens) tokens  —  modèle : \(session.modelName)"
        let altItem = NSMenuItem(title: altTitle, action: nil, keyEquivalent: "")
        altItem.isEnabled = false
        altItem.isAlternate = true
        altItem.keyEquivalentModifierMask = .option
        menu.addItem(altItem)
    }

    // MARK: - Actions

    @objc private func openProjectsFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.claude/projects"
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Ouvre Claude Desktop au premier plan
    @objc private func openSession(_ sender: NSMenuItem) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop")
        if let claude = apps.first {
            claude.activate(options: [.activateIgnoringOtherApps])
        } else {
            if let url = URL(string: "claude://") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    /// Action bidon pour garder les items de menu "enabled" (et préserver les couleurs)
    @objc private func noop() {}

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
