import Foundation
import UserNotifications

/// Gère les notifications système pour les seuils de remplissage du contexte.
/// Utilise le framework UserNotifications (UNUserNotificationCenter).
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Seuils de notification

    /// Seuils qui déclenchent une notification (en pourcentage)
    private enum Threshold: Int, CaseIterable {
        case warning = 80   // Avertissement
        case urgent = 90    // Urgent
        case full = 100     // Contexte plein
    }

    // MARK: - Propriétés

    /// Centre de notifications système
    private let center = UNUserNotificationCenter.current()

    /// Seuils déjà notifiés pour la session courante
    private var notifiedThresholds: Set<Int> = []

    /// Chemin de la session pour laquelle on a notifié
    private var notifiedSessionPath: String?

    /// Timer pour la notification répétée à 100%
    private var fullContextTimer: Timer?

    // MARK: - Initialisation

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    /// Demande la permission d'envoyer des notifications au premier lancement
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[ContextWatch] Erreur permission notifications : \(error.localizedDescription)")
            }
            if granted {
                print("[ContextWatch] Notifications autorisées")
            }
        }
    }

    // MARK: - Évaluation des seuils

    /// Évalue le pourcentage et envoie les notifications appropriées.
    /// Ne répète pas une notification pour le même seuil sauf si la session change.
    func evaluate(percentage: Int, sessionPath: String?) {
        // Si la session a changé → réinitialiser les seuils notifiés
        if sessionPath != notifiedSessionPath {
            notifiedThresholds.removeAll()
            notifiedSessionPath = sessionPath
            stopFullContextTimer()
        }

        // Vérifier chaque seuil
        for threshold in Threshold.allCases {
            if percentage >= threshold.rawValue && !notifiedThresholds.contains(threshold.rawValue) {
                sendNotification(for: threshold)
                notifiedThresholds.insert(threshold.rawValue)
            }
        }

        // Gérer la répétition à 100% (toutes les 60 secondes)
        if percentage >= 100 {
            startFullContextTimerIfNeeded()
        } else {
            stopFullContextTimer()
        }

        // Si le pourcentage redescend sous un seuil, le retirer des notifiés
        // → permet de re-notifier si ça remonte (ex: nouvelle session)
        for threshold in Threshold.allCases {
            if percentage < threshold.rawValue {
                notifiedThresholds.remove(threshold.rawValue)
            }
        }
    }

    // MARK: - Envoi des notifications

    /// Envoie une notification pour un seuil donné
    private func sendNotification(for threshold: Threshold) {
        let content = UNMutableNotificationContent()
        content.title = "ContextWatch"

        switch threshold {
        case .warning:
            content.body = "Contexte Claude Code à 80% — pense à faire un save"
            content.sound = .default
        case .urgent:
            content.body = "Contexte Claude Code à 90% — save urgent !"
            content.sound = .default
        case .full:
            content.body = "Contexte plein — plus possible d'écrire !"
            content.sound = .default
        }

        // Notification urgente pour 90% et 100%
        if #available(macOS 12.0, *) {
            switch threshold {
            case .warning:
                content.interruptionLevel = .timeSensitive
            case .urgent, .full:
                content.interruptionLevel = .timeSensitive
            }
        }

        let request = UNNotificationRequest(
            identifier: "contextwatch-\(threshold.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil // Envoi immédiat
        )

        center.add(request) { error in
            if let error = error {
                print("[ContextWatch] Erreur envoi notification : \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Timer pour 100%

    /// Démarre un timer qui répète la notification toutes les 60 secondes quand le contexte est plein
    private func startFullContextTimerIfNeeded() {
        guard fullContextTimer == nil else { return }

        fullContextTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.sendNotification(for: .full)
        }
    }

    /// Arrête le timer de répétition
    private func stopFullContextTimer() {
        fullContextTimer?.invalidate()
        fullContextTimer = nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Permet d'afficher les notifications même quand l'app est au premier plan
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
