import Cocoa
import UserNotifications

/// Délégué principal de l'application.
/// Gère le status item dans la menu bar, le menu contextuel,
/// et orchestre le SessionMonitor + NotificationManager.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Composants

    private var statusItem: NSStatusItem!
    private let sessionMonitor = SessionMonitor()
    private let notificationManager = NotificationManager()

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

        let text = "\(worst.icon) \(worst.percentage)%"
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

    // MARK: - Menu

    private func buildMenu(sessions: [SessionInfo]) {
        let menu = NSMenu()

        if sessions.isEmpty {
            let noSession = NSMenuItem(title: "Aucune session active", action: nil, keyEquivalent: "")
            noSession.isEnabled = false
            menu.addItem(noSession)
        } else {
            // En-tête
            let header = NSMenuItem(
                title: sessions.count == 1
                    ? "1 session active"
                    : "\(sessions.count) sessions actives",
                action: nil, keyEquivalent: ""
            )
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            // Une ligne par session, triée par % décroissant
            let sorted = sessions.sorted { $0.percentage > $1.percentage }
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
        // On garde l'item "enabled" avec une action bidon pour que macOS
        // n'écrase pas nos couleurs (isEnabled=false grise tout le texte)
        let item = NSMenuItem(title: "", action: #selector(noop), keyEquivalent: "")
        item.target = self

        let font = NSFont.menuFont(ofSize: 13)
        let boldFont = NSFont.boldSystemFont(ofSize: 13)
        let smallFont = NSFont.menuFont(ofSize: 11)
        let color = colorForPercentage(session.percentage)

        let str = NSMutableAttributedString()

        // Icône en couleur
        str.append(NSAttributedString(string: "\(session.icon) ", attributes: [
            .foregroundColor: color, .font: font
        ]))

        // Nom du projet — blanc franc, bien lisible
        str.append(NSAttributedString(string: session.displayName, attributes: [
            .foregroundColor: NSColor.white, .font: boldFont
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

    /// Action bidon pour garder les items de menu "enabled" (et préserver les couleurs)
    @objc private func noop() {}

    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
