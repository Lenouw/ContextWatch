import Foundation
import UserNotifications

/// Gère les notifications système pour les seuils de remplissage du contexte.
/// Supporte plusieurs sessions simultanées — chaque projet a son propre état de notification.
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Seuils

    private enum Threshold: Int, CaseIterable {
        case warning = 80
        case urgent  = 90
        case full    = 100
    }

    // MARK: - Propriétés

    private let center = UNUserNotificationCenter.current()

    /// Seuils déjà notifiés, indexés par chemin du dossier projet
    private var notifiedThresholds: [String: Set<Int>] = [:]

    /// Chemin du .jsonl actif qu'on surveillait la dernière fois, par projet
    /// → permet de détecter si une nouvelle session a démarré dans le même projet
    private var lastKnownJSONLPath: [String: String] = [:]

    /// Timers pour la notification répétée à 100%, par projet
    private var fullContextTimers: [String: Timer] = [:]

    // MARK: - Init

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[ContextWatch] Erreur permission notifications : \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Évaluation multi-sessions

    /// Évalue toutes les sessions actives et envoie les notifications appropriées.
    /// Chaque projet est suivi indépendamment.
    func evaluate(sessions: [SessionInfo]) {
        let activePaths = Set(sessions.map { $0.projectFolderPath })

        // Nettoyer les projets qui ne sont plus actifs
        for key in notifiedThresholds.keys where !activePaths.contains(key) {
            notifiedThresholds.removeValue(forKey: key)
            lastKnownJSONLPath.removeValue(forKey: key)
            stopTimer(for: key)
        }

        // Évaluer chaque session
        for session in sessions {
            evaluateSession(session)
        }
    }

    // MARK: - Évaluation d'une session

    private func evaluateSession(_ session: SessionInfo) {
        let key = session.projectFolderPath

        // Si le fichier .jsonl a changé → nouvelle conversation dans ce projet
        // On remet les compteurs à zéro pour ce projet
        if let knownPath = lastKnownJSONLPath[key], knownPath != session.path {
            notifiedThresholds[key] = []
            stopTimer(for: key)
        }
        lastKnownJSONLPath[key] = session.path

        // Initialiser le Set si nécessaire
        if notifiedThresholds[key] == nil {
            notifiedThresholds[key] = []
        }

        // Vérifier chaque seuil
        for threshold in Threshold.allCases {
            let alreadyNotified = notifiedThresholds[key]!.contains(threshold.rawValue)

            if session.percentage >= threshold.rawValue && !alreadyNotified {
                sendNotification(for: threshold, session: session)
                notifiedThresholds[key]!.insert(threshold.rawValue)
            }

            // Si le pourcentage redescend sous un seuil, on le retire
            // (permet de re-notifier si ça remonte — ex: nouvelle session dans le même projet)
            if session.percentage < threshold.rawValue {
                notifiedThresholds[key]!.remove(threshold.rawValue)
            }
        }

        // Timer répété à 100%
        if session.percentage >= 100 {
            startTimerIfNeeded(for: key, session: session)
        } else {
            stopTimer(for: key)
        }

        // Alerte images : seulement si au moins une image > 2000px
        if session.hasLargeImage {
            if session.imageCount > 20 && !(notifiedThresholds[key]!.contains(1020)) {
                sendImageAlert(session: session, level: .danger)
                notifiedThresholds[key]!.insert(1020)
            } else if session.imageCount > 15 && session.imageCount <= 20 && !(notifiedThresholds[key]!.contains(1015)) {
                sendImageAlert(session: session, level: .warning)
                notifiedThresholds[key]!.insert(1015)
            }
        }
    }

    // MARK: - Envoi des notifications

    private func sendNotification(for threshold: Threshold, session: SessionInfo) {
        let content = UNMutableNotificationContent()
        content.title = "ContextWatch — \(session.displayName)"

        switch threshold {
        case .warning:
            content.body = "Contexte à 80% — pense à faire un save"
            content.sound = .default
        case .urgent:
            content.body = "Contexte à 90% — save urgent !"
            content.sound = .default
        case .full:
            content.body = "Contexte plein — plus possible d'écrire !"
            content.sound = .default
        }

        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let request = UNNotificationRequest(
            identifier: "contextwatch-\(threshold.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[ContextWatch] Erreur notification : \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Alertes images

    private enum ImageAlertLevel {
        case warning  // > 15 images
        case danger   // > 20 images
    }

    private func sendImageAlert(session: SessionInfo, level: ImageAlertLevel) {
        let content = UNMutableNotificationContent()
        content.title = "ContextWatch — \(session.displayName)"

        switch level {
        case .warning:
            content.body = "⚠️ \(session.imageCount) images — au-delà de 20, les images > 2000px feront crasher la session !"
            content.sound = .default
        case .danger:
            content.body = "🚨 \(session.imageCount) images — limite dépassée ! Toute image > 2000px bloquera la session. Fais un save !"
            content.sound = .default
        }

        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let request = UNNotificationRequest(
            identifier: "contextwatch-img-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[ContextWatch] Erreur notification image : \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Timers

    private func startTimerIfNeeded(for key: String, session: SessionInfo) {
        guard fullContextTimers[key] == nil else { return }

        fullContextTimers[key] = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.sendNotification(for: .full, session: session)
        }
    }

    private func stopTimer(for key: String) {
        fullContextTimers[key]?.invalidate()
        fullContextTimers.removeValue(forKey: key)
    }

    // MARK: - Delegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
