import Foundation
import CoreServices

// MARK: - SessionActivity

/// État d'activité d'une session Claude Code
enum SessionActivity: Equatable {
    /// Claude est en train de générer une réponse ou d'exécuter des outils
    case working
    /// Claude a fini, attend l'input de l'utilisateur
    case waiting
    /// Pas d'activité depuis un moment
    case idle

    var icon: String {
        switch self {
        case .working: return "⚡"
        case .waiting: return "💬"
        case .idle:    return "💤"
        }
    }

    var label: String {
        switch self {
        case .working: return "En cours"
        case .waiting: return "En attente"
        case .idle:    return "Idle"
        }
    }
}

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
    /// État d'activité de la session
    let activity: SessionActivity
    /// La session utilise Computer Use (contrôle de l'ordinateur)
    let usesComputerUse: Bool
    /// Répertoire de travail réel du projet (cwd extrait du .jsonl)
    let cwd: String
    /// Nombre d'images dans la conversation
    let imageCount: Int
    /// Au moins une image dépasse 2000px (danger si > 20 images)
    let hasLargeImage: Bool

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

        // Compter les images et détecter les grandes (> 2000px)
        let (imgCount, imgHasLarge) = countImages(in: url.path)

        // Extraire les données de contexte, l'activité, Computer Use et cwd
        let (inputTokens, modelName, activity, computerUse, extractedCwd) = extractLastUsage(from: url.path, modDate: newestDate)

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
            modificationDate: newestDate,
            activity: activity,
            usesComputerUse: computerUse,
            cwd: extractedCwd,
            imageCount: imgCount,
            hasLargeImage: imgHasLarge
        )
    }

    // MARK: - Comptage des images

    /// Compte les images et détecte si au moins une dépasse 2000px.
    /// Lit le fichier entier mais ne parse que les lignes contenant des images.
    /// Retourne (nombre d'images, au moins une > 2000px).
    private func countImages(in path: String) -> (count: Int, hasLarge: Bool) {
        guard let data = fileManager.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return (0, false) }

        var count = 0
        var hasLarge = false
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            guard !line.isEmpty else { continue }
            guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"") else { continue }
            guard !line.contains("<synthetic>") else { continue }
            guard line.contains("\"type\":\"image\"") || line.contains("\"type\": \"image\"") else { continue }

            // Compter les images dans cette ligne
            for pattern in ["\"type\":\"image\"", "\"type\": \"image\""] {
                var searchRange = line.startIndex..<line.endIndex
                while let range = line.range(of: pattern, range: searchRange) {
                    count += 1

                    // Détecter les dimensions depuis le base64 (PNG header)
                    // Chercher le bloc "data":"..." le plus proche après cette image
                    if !hasLarge {
                        hasLarge = checkImageDimensions(in: line, near: range.upperBound)
                    }

                    searchRange = range.upperBound..<line.endIndex
                }
            }
        }
        return (count, hasLarge)
    }

    /// Vérifie si une image encodée en base64 dépasse 2000px.
    /// Lit l'en-tête PNG (largeur/hauteur aux octets 16-23) ou estime via la taille du base64.
    private func checkImageDimensions(in line: String, near position: String.Index) -> Bool {
        // Chercher "data":"..." proche de la position
        let searchEnd = line.index(position, offsetBy: min(500, line.distance(from: position, to: line.endIndex)))
        let vicinity = String(line[position..<searchEnd])

        guard let dataStart = vicinity.range(of: "\"data\":\"")?.upperBound
              ?? vicinity.range(of: "\"data\": \"")?.upperBound
        else { return false }

        let b64Start = vicinity[dataStart...]
        // Prendre les 48 premiers caractères base64 (= 36 octets décodés, assez pour le header PNG)
        let b64Prefix = String(b64Start.prefix(48)).replacingOccurrences(of: "\"", with: "")

        guard let headerData = Data(base64Encoded: b64Prefix) else {
            // Si on ne peut pas décoder le header, estimer par la taille du base64 total
            // Un bloc base64 de > 500K caractères = probablement une grande image
            if let dataEnd = b64Start.range(of: "\"")?.lowerBound {
                let b64Length = b64Start.distance(from: b64Start.startIndex, to: dataEnd)
                return b64Length > 500_000
            }
            return false
        }

        // PNG : les octets 0-7 sont le magic number (89 50 4E 47 0D 0A 1A 0A)
        // Octets 16-19 = largeur (big-endian), 20-23 = hauteur (big-endian)
        if headerData.count >= 24 &&
           headerData[0] == 0x89 && headerData[1] == 0x50 { // PNG magic
            let width = Int(headerData[16]) << 24 | Int(headerData[17]) << 16 | Int(headerData[18]) << 8 | Int(headerData[19])
            let height = Int(headerData[20]) << 24 | Int(headerData[21]) << 16 | Int(headerData[22]) << 8 | Int(headerData[23])
            return width > 2000 || height > 2000
        }

        // JPEG : pas facile à parser depuis le header seul, on estime par la taille
        if headerData.count >= 2 && headerData[0] == 0xFF && headerData[1] == 0xD8 { // JPEG magic
            if let dataEnd = b64Start.range(of: "\"")?.lowerBound {
                let b64Length = b64Start.distance(from: b64Start.startIndex, to: dataEnd)
                // JPEG > 400K base64 chars ≈ > 300KB ≈ probablement > 2000px
                return b64Length > 400_000
            }
        }

        return false
    }

    // MARK: - Extraction des tokens (lecture minimale du fichier)

    /// Lit les derniers ~100 Ko du fichier .jsonl pour extraire :
    /// - Le total de tokens du dernier message assistant (= taille réelle du contexte)
    /// - Le nom du modèle
    /// - L'état d'activité de la session (working/waiting/idle)
    ///
    /// Le vrai contexte = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
    /// car l'API Anthropic sépare les tokens non-cachés, nouvellement cachés, et lus depuis le cache.
    private func extractLastUsage(from path: String, modDate: Date) -> (inputTokens: Int, model: String, activity: SessionActivity, computerUse: Bool, cwd: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return (0, "unknown", .idle, false, "")
        }
        defer { handle.closeFile() }

        // Lire les derniers 100 Ko (largement suffisant pour le dernier message assistant)
        let fileEnd = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileEnd, 100_000)
        handle.seek(toFileOffset: fileEnd - readSize)
        let data = handle.readDataToEndOfFile()

        guard let text = String(data: data, encoding: .utf8) else {
            return (0, "unknown", .idle, false, "")
        }

        // Détection rapide de Computer Use dans le chunk lu
        let hasComputerUse = text.contains("mcp__computer-use__")

        let lines = text.components(separatedBy: "\n").reversed()

        // --- Détection de l'activité ---
        let secondsSinceModified = Date().timeIntervalSince(modDate)
        var activity: SessionActivity = .idle

        // Chercher le dernier message significatif pour déterminer l'état
        for line in lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let topType = json["type"] as? String
            else { continue }

            // Ignorer les types internes
            if topType == "queue-operation" || topType == "system" { continue }

            if topType == "progress" {
                // Un hook/outil est en cours → working (si récent)
                if secondsSinceModified < 60 {
                    activity = .working
                }
                break
            }

            if topType == "assistant" {
                if let message = json["message"] as? [String: Any] {
                    let msgModel = message["model"] as? String ?? ""
                    // Ignorer les messages synthetic (crash/système)
                    if msgModel.contains("synthetic") { continue }

                    if let stopReason = message["stop_reason"] as? String {
                        if stopReason == "tool_use" {
                            activity = secondsSinceModified < 120 ? .working : .idle
                        } else {
                            if secondsSinceModified < 300 {
                                activity = .waiting
                            } else {
                                activity = .idle
                            }
                        }
                    }
                }
                break
            }

            if topType == "user" {
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]],
                   content.contains(where: { ($0["type"] as? String) == "tool_result" }) {
                    // Résultat d'outil renvoyé → Claude va continuer → working
                    activity = secondsSinceModified < 120 ? .working : .idle
                } else {
                    // L'utilisateur vient d'écrire → Claude va répondre → working
                    activity = secondsSinceModified < 60 ? .working : .idle
                }
                break
            }

            break
        }

        // Fallback basé sur le mtime seul
        if activity == .idle && secondsSinceModified < 30 {
            activity = .working
        }

        // --- Extraction des tokens (dernier assistant principal, PAS synthetic) ---
        var totalContext = 0
        var model = "unknown"

        for line in lines {
            guard line.contains("\"input_tokens\"") else { continue }
            // Filtre rapide : ignorer les messages synthetic (crash/système)
            guard !line.contains("<synthetic>") else { continue }

            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            guard let topType = json["type"] as? String, topType == "assistant" else { continue }
            // Ignorer aussi les messages "progress" (sous-agents)
            if json["isSidechain"] as? Bool == true { continue }

            guard let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let msgModel = message["model"] as? String ?? "unknown"
            // Double vérification : ignorer les modèles synthetic
            guard !msgModel.contains("synthetic") else { continue }

            model = msgModel

            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            totalContext = inputTokens + cacheCreation + cacheRead
            break
        }

        // Extraire le cwd depuis la première ligne qui en contient un
        var extractedCwd = ""
        for line in lines {
            guard line.contains("\"cwd\"") else { continue }
            guard let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let cwd = json["cwd"] as? String
            else { continue }
            extractedCwd = cwd
            break
        }

        return (totalContext, model, activity, hasComputerUse, extractedCwd)
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
            zip(newSessions, sessions).contains {
                $0.path != $1.path || $0.percentage != $1.percentage || $0.activity != $1.activity || $0.usesComputerUse != $1.usesComputerUse || $0.imageCount != $1.imageCount
            }

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
