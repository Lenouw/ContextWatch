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
- **Génération icône** : Python Pillow (script de génération, pas de dépendance runtime)

## Dernière mise à jour
2026-03-27 — App complète codée, compilée avec succès, icône intégrée

## Ce qu'on a fait
- 2026-03-27 : App complète codée et compilée — les 4 fichiers Swift, Info.plist, projet Xcode, build OK du premier coup
- 2026-03-27 : Icône de l'app créée avec Pillow (anneau de progression gradient cyan→vert→jaune→orange sur fond sombre, symbole %), convertie en .icns, intégrée dans le projet Xcode
- 2026-03-27 : App recompilée avec l'icône — BUILD SUCCEEDED, .app copié dans Exports de app/
- 2026-03-27 : Plan d'action validé — 6 phases définies (structure Xcode, entry point, SessionMonitor, NotificationManager, AppDelegate, test/commit)
- 2026-03-27 : Initialisation du projet, création du dépôt Git et du CONTEXT.md

## Où on en est
L'app est **complète et fonctionnelle** :
- Les 4 fichiers Swift sont écrits et compilent sans erreur
- Le projet Xcode est configuré (project.pbxproj, Info.plist avec LSUIElement=true)
- L'icône est intégrée (AppIcon.icns référencé dans Info.plist + Resources build phase)
- Le .app compilé est disponible dans `Exports de app/ContextWatch.app`
- **Pas encore testé en conditions réelles** (lancer l'app et vérifier la détection de session)

### Fichiers du projet
```
ContextWatch/
  ContextWatch.xcodeproj/
    project.pbxproj              — projet Xcode complet
    project.xcworkspace/         — workspace Xcode
  ContextWatch/
    ContextWatchApp.swift         — point d'entrée @main (12 lignes)
    AppDelegate.swift             — NSStatusItem, menu contextuel, orchestration (170 lignes)
    SessionMonitor.swift          — FSEventStream, scan .jsonl, calcul % (175 lignes)
    NotificationManager.swift     — UNUserNotificationCenter, seuils 80/90/100% (140 lignes)
    Info.plist                    — LSUIElement=true, CFBundleIconFile=AppIcon
    AppIcon.icns                  — icône de l'app (791 Ko)
  AppIcon_1024.png               — source de l'icône (1024x1024)
```

## Architecture et décisions
- **AppKit pur** : pas de SwiftUI, pour compatibilité et contrôle total sur la menu bar
- **LSUIElement = true** : l'app vit exclusivement dans la menu bar, pas d'icône dans le Dock
- **FSEventStream** : surveillance native macOS des fichiers via `FSEventStreamSetDispatchQueue` (API moderne), pas de Timer/polling — réactif et économe en ressources. Latence de 1 seconde.
- **Taille seule** : on ne lit JAMAIS le contenu des .jsonl, seulement leur taille via `url.resourceValues(forKeys:)` (performance + vie privée)
- **Seuil 900 Ko** : constante `SessionMonitor.maxContextSizeKB`, facilement modifiable. Estimation empirique du contexte utile max.
- **Non sandboxé** : nécessaire pour accéder à `~/.claude/projects/` sans restrictions. Pas d'entitlements, signature "Sign to Run Locally".
- **Notifications .timeSensitive** : on utilise `interruptionLevel = .timeSensitive` (pas `.critical` qui nécessite un entitlement Apple spécial). Son `.default` pour tous les seuils.
- **Menu item alternatif** : `isAlternate = true` avec `keyEquivalentModifierMask = .option` pour afficher la taille exacte du .jsonl quand on tient Option — permet la calibration manuelle du seuil de 900 Ko.
- **Icône générée via Pillow** : rendu à 2048x2048 puis downscale LANCZOS à 1024 pour anti-aliasing propre. Conversion en .icns via `iconutil`.

## Ce qu'il reste à faire
- [x] Créer la structure du projet Xcode (dossiers, fichiers, .xcodeproj)
- [x] Implémenter ContextWatchApp.swift — point d'entrée @main
- [x] Implémenter AppDelegate.swift — menu bar, status item, menu contextuel
- [x] Implémenter SessionMonitor.swift — FSEventStream, détection session active, calcul %
- [x] Implémenter NotificationManager.swift — gestion des seuils et notifications système
- [x] Créer Info.plist avec LSUIElement = true
- [x] Tester la compilation
- [x] Créer et intégrer l'icône de l'app
- [ ] Tester l'app en conditions réelles (lancer, vérifier détection de session, notifications)
- [ ] Calibrer le seuil de 900 Ko si nécessaire après tests réels
- [ ] Éventuellement ajouter l'app au Login Items pour lancement automatique au démarrage
