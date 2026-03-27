import Foundation
import CoreServices

/// Surveille les fichiers de session Claude Code (.jsonl) dans ~/.claude/projects/
/// et calcule le pourcentage de remplissage du contexte.
/// Ne lit JAMAIS le contenu des fichiers — seulement leur taille (attributs fichier).
class SessionMonitor {

    // MARK: - Constantes

    /// Taille maximale de référence en Ko (calibrable).
    /// 900 Ko correspond empiriquement à ~100% du contexte utile.
    static let maxContextSizeKB: Double = 900.0

    // MARK: - Propriétés publiques

    /// Chemin du fichier .jsonl de la session active
    private(set) var activeSessionPath: String?

    /// Taille du fichier actif en Ko
    private(set) var activeSessionSizeKB: Double = 0

    /// Pourcentage de remplissage (0–100, plafonné)
    private(set) var percentage: Int = 0

    /// Date de dernière mise à jour
    private(set) var lastUpdate: Date?

    /// Callback appelé à chaque changement détecté.
    /// Paramètres : pourcentage, taille en Ko, chemin de la session active.
    var onUpdate: ((Int, Double, String?) -> Void)?

    // MARK: - Propriétés privées

    /// Référence au stream FSEvents
    private var eventStream: FSEventStreamRef?

    /// Chemin surveillé : ~/.claude/projects/
    private let watchedPath: String

    /// FileManager partagé
    private let fileManager = FileManager.default

    // MARK: - Initialisation

    init() {
        let home = fileManager.homeDirectoryForCurrentUser.path
        watchedPath = "\(home)/.claude/projects"
    }

    // MARK: - Surveillance

    /// Démarre la surveillance du dossier ~/.claude/projects/
    func startMonitoring() {
        // Scan initial pour détecter une session déjà en cours
        scanForActiveSession()

        // Configurer le FSEventStream (fonctionne même si le dossier n'existe pas encore)
        setupEventStream()
    }

    /// Arrête la surveillance et libère les ressources
    func stopMonitoring() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    // MARK: - FSEventStream

    /// Configure le FSEventStream pour surveiller le dossier récursivement
    private func setupEventStream() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Callback C — récupère le SessionMonitor via le pointeur info
        let callback: FSEventStreamCallback = {
            (_, clientInfo, _, _, _, _) in
            guard let info = clientInfo else { return }
            let monitor = Unmanaged<SessionMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.scanForActiveSession()
        }

        let pathsToWatch = [watchedPath] as CFArray

        eventStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // Latence 1s — bon compromis réactivité/performance
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = eventStream {
            // Utiliser DispatchQueue plutôt que RunLoop (plus moderne)
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    // MARK: - Scan des sessions

    /// Recherche le fichier .jsonl le plus récemment modifié
    /// et calcule le pourcentage de remplissage du contexte.
    func scanForActiveSession() {
        // Vérifier que le dossier existe
        guard fileManager.fileExists(atPath: watchedPath) else {
            updateState(path: nil, sizeKB: 0, pct: 0)
            return
        }

        // Recherche récursive de tous les fichiers .jsonl
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: watchedPath),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            updateState(path: nil, sizeKB: 0, pct: 0)
            return
        }

        var mostRecentPath: String?
        var mostRecentDate: Date = .distantPast
        var mostRecentSize: Int = 0

        for case let url as URL in enumerator {
            // Ne garder que les fichiers .jsonl
            guard url.pathExtension == "jsonl" else { continue }

            do {
                let resourceValues = try url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )

                if let modDate = resourceValues.contentModificationDate,
                   modDate > mostRecentDate {
                    mostRecentDate = modDate
                    mostRecentPath = url.path
                    mostRecentSize = resourceValues.fileSize ?? 0
                }
            } catch {
                // Ignorer les fichiers inaccessibles
                continue
            }
        }

        // Si aucun fichier .jsonl trouvé
        guard let path = mostRecentPath else {
            updateState(path: nil, sizeKB: 0, pct: 0)
            return
        }

        // Calcul du pourcentage : (taille / 900 Ko) * 100, plafonné à 100%
        let sizeKB = Double(mostRecentSize) / 1024.0
        let pct = min(Int((sizeKB / SessionMonitor.maxContextSizeKB) * 100.0), 100)

        updateState(path: path, sizeKB: sizeKB, pct: pct)
    }

    // MARK: - Mise à jour de l'état

    /// Met à jour l'état interne et notifie le callback si changement
    private func updateState(path: String?, sizeKB: Double, pct: Int) {
        let changed = (path != activeSessionPath || pct != percentage)

        activeSessionPath = path
        activeSessionSizeKB = sizeKB
        percentage = pct
        lastUpdate = Date()

        if changed {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onUpdate?(self.percentage, self.activeSessionSizeKB, self.activeSessionPath)
            }
        }
    }

    // MARK: - Utilitaires

    /// Retourne un nom court pour la session active (dossier parent / nom du fichier)
    var activeSessionShortName: String {
        guard let path = activeSessionPath else { return "—" }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().lastPathComponent
        return "\(parent)/\(url.lastPathComponent)"
    }
}
