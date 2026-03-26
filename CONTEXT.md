# Contexte du projet

## Projet
**ContextWatch** — Application macOS native (menu bar app) qui surveille en temps réel le remplissage du contexte des sessions Claude Code. Elle lit la taille des fichiers .jsonl dans `~/.claude/projects/` et alerte l'utilisateur avant que le contexte soit plein pour qu'il puisse sauvegarder à temps.

## Stack technique
- **Langage** : Swift
- **Framework UI** : AppKit (pas de SwiftUI)
- **Target** : macOS 13+
- **Surveillance fichiers** : FSEventStream (natif macOS, pas de polling)
- **Notifications** : UserNotifications (UNUserNotificationCenter)
- **Dépendances externes** : aucune
- **Projet** : Xcode project (.xcodeproj)

## Dernière mise à jour
2026-03-27 — Initialisation

## Ce qu'on a fait
- 2026-03-27 : Initialisation du projet, création du dépôt Git et du CONTEXT.md

## Où on en est
Le projet vient d'être initialisé. Aucun code n'a encore été écrit. La spécification est complète et détaillée. On va créer un plan d'action puis coder l'app.

## Architecture et décisions
- **AppKit pur** : pas de SwiftUI, pour compatibilité et contrôle total sur la menu bar
- **LSUIElement = true** : l'app vit exclusivement dans la menu bar, pas d'icône dans le Dock
- **FSEventStream** : surveillance native macOS des fichiers, pas de Timer/polling — réactif et économe en ressources
- **Taille seule** : on ne lit JAMAIS le contenu des .jsonl, seulement leur taille via les attributs fichier (performance + vie privée)
- **Seuil 900 Ko** : estimation empirique du contexte utile max, constante facilement modifiable
- **Non sandboxé** : nécessaire pour accéder à ~/.claude/projects/ sans restrictions

## Ce qu'il reste à faire
- [ ] Créer la structure du projet Xcode (dossiers, fichiers, .xcodeproj)
- [ ] Implémenter ContextWatchApp.swift — point d'entrée @main
- [ ] Implémenter AppDelegate.swift — menu bar, status item, menu contextuel
- [ ] Implémenter SessionMonitor.swift — FSEventStream, détection session active, calcul %
- [ ] Implémenter NotificationManager.swift — gestion des seuils et notifications système
- [ ] Créer Info.plist avec LSUIElement = true
- [ ] Tester la compilation et le fonctionnement
- [ ] Calibrer le seuil de 900 Ko si nécessaire
