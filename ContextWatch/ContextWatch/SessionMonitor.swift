import Foundation
import CoreServices

// MARK: - SessionInfo

/// Représente une session Claude Code active (un projet = un .jsonl actif)
struct SessionInfo {
    /// Chemin complet du .jsonl le plus récent pour ce projet
    let path: String
    /// Chemin du dossier projet
    let projectFolderPath: String
    /// Nombre de tokens en entrée du dernier appel API (= taille réelle du contexte)
    let inputTokens: Int
    /// Taille maximale du contexte selon le modèle (en tokens)
    let maxContextTokens: Int
    /// Pourcentage de remplissage (0–100, plafonné)
    let percentage: Int
    /// Nom du modèle utilisé (ex: "claude-sonnet-4-6-20250327")
    let modelName: String
    /// Date de dernière modification du .jsonl
    let modificationDate: Date

    /// Nom lisible du projet, décodé depuis le nom de dossier Claude Code
    var displayName: String {
        let folderName = URL(fileURLWithPath: projectFolderPath).lastPathComponent
        let marker = "-CLAUDE-CODE-"
        if let range = folderName.range(of: marker) {
            var part = String(folderName[range.upperBound...])
            part = part.replacingOccurrences(of: "---", with: " ")
            part = part.replacingOccurrences(of: "-", with: " ")
            while part.contains("  ") {
                part = part.replacingOccurrences(of: "  ", with: " ")
            }
            let cleaned = part.trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty { return cleaned }
        }
        let parts = folderName.components(separatedBy: "-").filter { !$0.isEmpty }
        return parts.suffix(4).joined(separator: " ")
    }

    /// Icône selon le niveau de remplissage
    var icon: String {
        switch percentage {
        case 0...60:  return "◯"
        case 61...79: return "◔"
        case 80...89: return "◑"
        case 90...99: return "◕"
        default:      return "●"
        }
    }

    /// Nom court du modèle pour affichage (ex: "Sonnet 4.6", "Opus 4.6")
    var modelShortName: String {
        if modelName.contains("opus")   { return "Opus" }
        if modelName.contains("sonnet") { return "Sonnet" }
        if modelName.contains("haiku")  { return "Haiku" }
        return modelName
    }

    /// Tokens input formatés pour affichage (ex: "182K", "1.2M")
    var inputTokensFormatted: String {
        formatTokens(inputTokens)
    }

    /// Tokens max formatés pour affichage
    var maxTokensFormatted: String {
        formatTokens(maxContextTokens)
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            let val = Double(n) / 1_000_000.0
            return val.truncatingRemainder(dividingBy: 1.0) == 0
                ? "\(Int(val))M"
                : String(format: "%.1fM", val)
        } else if n >= 1_000 {
            let val = Double(n) / 1_000.0
            return val.truncatingRemainder(dividingBy: 1.0) == 0
                ? "\(Int(val))K"
                : String(format: "%.0fK", val)
        }
        return "\(n)"
    }
}

// MARK: - SessionMonitor

/// Surveille ~/.claude/projects/ et calcule le remplissage du contexte
/// en lisant les token counts des messages assistant (usage.input_tokens).
/// Ceci est le vrai indicateur de contexte, pas la taille du fichier.
class SessionMonitor {

    // MARK: - Constantes

    /// Limite de tokens par modèle (calibrable)
    static let contextLimits: [String: Int] = [
        "opus":   1_000_000,   // Opus 4.6 — 1M tokens
        "sonnet":   200_000,   // Sonnet — 200K tokens
        "haiku":    200_000,   // Haiku — 200K tokens
    ]

    /// Limite par défaut si le modèle est inconnu
    static let defaultContextLimit: Int = 200_000

    /// Fenêtre de temps pour considérer une session comme active (heures)
    static let activeWindowHours: Double = 48.0

    // MARK: - Propriétés publiques

    private(set) var sessions: [SessionInfo] = []
    private(set) var lastUpdate: Date?
    var onUpdate: (([SessionInfo]) -> Void)?

    // MARK: - Propriétés privées

    private var eventStream: FSEventStreamRef?
    private let watchedPath: String
    private let fileManager = FileManager.default

    init() {
        let home = fileManager.homeDirectoryForCurrentUser.path
        watchedPath = "\(home)/.claude/projects"
    }

    // MARK: - Surveillance

    func startMonitoring() {
        scanAllSessions()
        setupEventStream()
    }

    func stopMonitoring() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    // MARK: - FSEventStream

    private func setupEventStream() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (_, clientInfo, _, _, _, _) in
            guard let info = clientInfo else { return }
            Unmanaged<SessionMonitor>.fromOpaque(info).takeUnretainedValue().scanAllSessions()
        }

        let pathsToWatch = [watchedPath] as CFArray
        eventStream = FSEventStreamCreate(
            nil, callback, &context, pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    // MARK: - Scan multi-sessions

    func scanAllSessions() {
        guard fileManager.fileExists(atPath: watchedPath) else {
            updateState(sessions: [])
            return
        }

        let projectsURL = URL(fileURLWithPath: watchedPath)
        guard let projectFolders = try? fileManager.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            updateState(sessions: [])
            return
        }

        let cutoffDate = Date().addingTimeInterval(-SessionMonitor.activeWindowHours * 3600)
        var found: [SessionInfo] = []

        for folder in projectFolders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }

            if let session = newestActiveSession(in: folder, after: cutoffDate) {
                found.append(session)
            }
        }

        found.sort { $0.modificationDate > $1.modificationDate }
        updateState(sessions: found)
    }

    /// Trouve le .jsonl le plus récent dans un projet et lit ses données de contexte
    private func newestActiveSession(in folder: URL, after cutoffDate: Date) -> SessionInfo? {
        guard let files = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // Trouver le .jsonl le plus récent
        var newestDate: Date = cutoffDate
        var newestURL: URL? = nil

        for file in files {
            guard file.pathExtension == "jsonl" else { continue }
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  modDate > newestDate
            else { continue }

            newestDate = modDate
            newestURL = file
        }

        guard let url = newestURL else { return nil }

        // Extraire les données de contexte du dernier message assistant
        let (inputTokens, modelName) = extractLastUsage(from: url.path)

        // Déterminer la limite de contexte selon le modèle
        let maxTokens = contextLimit(for: modelName)

        // Calculer le pourcentage
        let pct: Int
        if inputTokens > 0 {
            pct = min(Int((Double(inputTokens) / Double(maxTokens)) * 100.0), 100)
        } else {
            pct = 0
        }

        return SessionInfo(
            path: url.path,
            projectFolderPath: folder.path,
            inputTokens: inputTokens,
            maxContextTokens: maxTokens,
            percentage: pct,
            modelName: modelName,
            modificationDate: newestDate
        )
    }

    // MARK: - Extraction des tokens (lecture minimale du fichier)

    /// Lit les derniers ~100 Ko du fichier .jsonl et cherche le dernier message assistant
    /// (type "assistant" au top-level, pas "progress" qui sont des sous-agents)
    /// pour en extraire le total de tokens et le nom du modèle.
    ///
    /// Le vrai contexte = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
    /// car l'API Anthropic sépare les tokens non-cachés, nouvellement cachés, et lus depuis le cache.
    private func extractLastUsage(from path: String) -> (inputTokens: Int, model: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return (0, "unknown")
        }
        defer { handle.closeFile() }

        // Lire les derniers 100 Ko (largement suffisant pour le dernier message assistant)
        let fileEnd = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileEnd, 100_000)
        handle.seek(toFileOffset: fileEnd - readSize)
        let data = handle.readDataToEndOfFile()

        guard let text = String(data: data, encoding: .utf8) else {
            return (0, "unknown")
        }

        // Parcourir les lignes depuis la fin pour trouver le dernier assistant principal
        let lines = text.components(separatedBy: "\n").reversed()

        for line in lines {
            // Filtre rapide : doit contenir "input_tokens" ET être un message assistant
            guard line.contains("\"input_tokens\"") else { continue }

            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            // IMPORTANT : ne prendre que les messages "assistant" au top-level
            // Ignorer "progress" (sous-agents) et "queue-operation" (internes)
            guard let topType = json["type"] as? String, topType == "assistant" else { continue }

            // Extraire usage depuis message.usage
            guard let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let model = message["model"] as? String ?? "unknown"

            // Le vrai nombre de tokens dans le contexte =
            // input_tokens (non-cachés) + cache_creation (nouveaux dans le cache) + cache_read (lus depuis le cache)
            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let totalContext = inputTokens + cacheCreation + cacheRead

            return (totalContext, model)
        }

        return (0, "unknown")
    }

    /// Retourne la limite de contexte (en tokens) pour un modèle donné
    private func contextLimit(for model: String) -> Int {
        let lower = model.lowercased()
        for (keyword, limit) in SessionMonitor.contextLimits {
            if lower.contains(keyword) {
                return limit
            }
        }
        return SessionMonitor.defaultContextLimit
    }

    // MARK: - État

    private func updateState(sessions newSessions: [SessionInfo]) {
        let changed = newSessions.count != sessions.count ||
            zip(newSessions, sessions).contains { $0.path != $1.path || $0.percentage != $1.percentage }

        sessions = newSessions
        lastUpdate = Date()

        if changed {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onUpdate?(self.sessions)
            }
        }
    }

    /// Session la plus critique
    var mostCriticalSession: SessionInfo? {
        sessions.max(by: { $0.percentage < $1.percentage })
    }
}
