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
2026-03-27 — Save après validation du plan d'action

## Ce qu'on a fait
- 2026-03-27 : Plan d'action validé — 6 phases définies (structure Xcode, entry point, SessionMonitor, NotificationManager, AppDelegate, test/commit)
- 2026-03-27 : Initialisation du projet, création du dépôt Git et du CONTEXT.md

## Où on en est
Le projet est initialisé avec Git. La spécification complète est définie (voir le prompt initial). Un plan d'action en 6 phases a été présenté et validé par l'utilisateur. Aucun code Swift n'a encore été écrit. Prêt à coder.

### Plan d'action validé
1. **Phase 1** : Structure Xcode (dossiers, project.pbxproj, Info.plist, entitlements)
2. **Phase 2** : ContextWatchApp.swift — entry point @main
3. **Phase 3** : SessionMonitor.swift — FSEventStream, scan .jsonl, calcul %
4. **Phase 4** : NotificationManager.swift — UNUserNotificationCenter, seuils 80/90/100%
5. **Phase 5** : AppDelegate.swift — NSStatusItem, menu, assemblage de tout
6. **Phase 6** : Test compilation + commit final

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
