import Cocoa
import UserNotifications

/// Délégué principal de l'application.
/// Gère le status item dans la menu bar, le menu contextuel,
/// et orchestre le SessionMonitor + NotificationManager.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Composants

    /// Icône dans la menu bar
    private var statusItem: NSStatusItem!

    /// Moniteur de session Claude Code
    private let sessionMonitor = SessionMonitor()

    /// Gestionnaire de notifications système
    private let notificationManager = NotificationManager()

    // MARK: - Cycle de vie

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Créer le status item dans la menu bar (taille variable selon le texte)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Affichage initial : aucune session
        updateStatusItemTitle(percentage: 0, sessionPath: nil)

        // Construire le menu contextuel
        buildMenu()

        // Demander la permission pour les notifications
        notificationManager.requestPermission()

        // Configurer le callback du moniteur de session
        sessionMonitor.onUpdate = { [weak self] percentage, sizeKB, sessionPath in
            self?.handleUpdate(percentage: percentage, sizeKB: sizeKB, sessionPath: sessionPath)
        }

        // Démarrer la surveillance de ~/.claude/projects/
        sessionMonitor.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionMonitor.stopMonitoring()
    }

    // MARK: - Mise à jour de l'affichage

    /// Appelé quand le moniteur détecte un changement de session ou de taille
    private func handleUpdate(percentage: Int, sizeKB: Double, sessionPath: String?) {
        updateStatusItemTitle(percentage: percentage, sessionPath: sessionPath)
        buildMenu()
        notificationManager.evaluate(percentage: percentage, sessionPath: sessionPath)
    }

    /// Met à jour le titre du status item avec l'icône appropriée et le pourcentage
    private func updateStatusItemTitle(percentage: Int, sessionPath: String?) {
        guard let button = statusItem.button else { return }

        // Aucune session trouvée → afficher "—"
        guard sessionPath != nil else {
            button.title = "◯ —"
            return
        }

        // Icône selon le niveau de remplissage
        let icon: String
        switch percentage {
        case 0...60:
            icon = "◯"     // Vide / confortable
        case 61...79:
            icon = "◔"     // Un quart rempli
        case 80...89:
            icon = "◑"     // À moitié — attention
        case 90...99:
            icon = "◕"     // Presque plein — urgent
        default:
            icon = "●"     // Plein
        }

        button.title = "\(icon) \(percentage)%"
    }

    // MARK: - Construction du menu

    /// Construit le menu contextuel du status item
    private func buildMenu() {
        let menu = NSMenu()

        // — Session active —
        let sessionName = sessionMonitor.activeSessionShortName
        let sessionItem = NSMenuItem(
            title: "Session active : \(sessionName)",
            action: nil,
            keyEquivalent: ""
        )
        sessionItem.isEnabled = false
        menu.addItem(sessionItem)

        // — Contexte : pourcentage et taille —
        let sizeStr = String(format: "%.0f", sessionMonitor.activeSessionSizeKB)
        let maxStr = String(format: "%.0f", SessionMonitor.maxContextSizeKB)
        let contextItem = NSMenuItem(
            title: "Contexte : \(sessionMonitor.percentage)% (\(sizeStr) Ko / \(maxStr) Ko)",
            action: nil,
            keyEquivalent: ""
        )
        contextItem.isEnabled = false
        menu.addItem(contextItem)

        // — Option cachée : taille exacte (visible avec touche Option) —
        // Remplace la ligne "Contexte" quand l'utilisateur tient Option
        let calibrationItem = NSMenuItem(
            title: "Taille exacte : \(String(format: "%.2f", sessionMonitor.activeSessionSizeKB)) Ko",
            action: nil,
            keyEquivalent: ""
        )
        calibrationItem.isEnabled = false
        calibrationItem.isAlternate = true
        calibrationItem.keyEquivalentModifierMask = .option
        menu.addItem(calibrationItem)

        // — Dernière mise à jour —
        let timeStr: String
        if let lastUpdate = sessionMonitor.lastUpdate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            timeStr = formatter.string(from: lastUpdate)
        } else {
            timeStr = "—"
        }
        let updateItem = NSMenuItem(
            title: "Dernière mise à jour : \(timeStr)",
            action: nil,
            keyEquivalent: ""
        )
        updateItem.isEnabled = false
        menu.addItem(updateItem)

        // — Séparateur —
        menu.addItem(.separator())

        // — Ouvrir le dossier dans le Finder —
        let openItem = NSMenuItem(
            title: "Ouvrir ~/.claude/projects/",
            action: #selector(openProjectsFolder),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        // — Séparateur —
        menu.addItem(.separator())

        // — Quitter —
        let quitItem = NSMenuItem(
            title: "Quitter",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions du menu

    /// Ouvre le dossier ~/.claude/projects/ dans le Finder
    @objc private func openProjectsFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.claude/projects"

        // Créer le dossier s'il n'existe pas encore
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true
            )
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Quitte l'application
    @objc private func quit() {
        NSApplication.shared.terminate(self)
    }
}
