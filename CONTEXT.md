# Contexte du projet

## Projet
**ContextWatch** — Application macOS native (menu bar app) qui surveille en temps réel le remplissage du contexte de TOUTES les sessions Claude Code actives simultanément. Elle lit les token counts dans les fichiers .jsonl de `~/.claude/projects/` et alerte l'utilisateur avant que le contexte soit plein pour qu'il puisse sauvegarder à temps.

## Stack technique
- **Langage** : Swift
- **Framework UI** : AppKit (pas de SwiftUI)
- **Target** : macOS 13+
- **Surveillance fichiers** : FSEventStream (natif macOS, pas de polling)
- **Notifications** : UserNotifications (UNUserNotificationCenter)
- **Dépendances externes** : aucune
- **Projet** : Xcode project (.xcodeproj)
- **Génération icône** : Python Pillow (script `generate_icon.py`, pas de dépendance runtime)

## Dernière mise à jour
2026-03-27 21h — V2 complète : multi-sessions, tokens réels, code couleur, nouveau logo

## Ce qu'on a fait
- 2026-03-27 21h : Design du menu amélioré — noms de projets en blanc gras, pourcentages en couleur (vert/jaune/orange/rouge), tokens et modèle en gris. Items "enabled" avec action noop pour éviter le grisage macOS.
- 2026-03-27 20h : Ajout du code couleur dans le menu ET la menu bar — vert (0-60%), jaune (61-79%), orange (80-89%), rouge (90-100%). Affichage du modèle (Sonnet/Opus/Haiku) sur chaque ligne.
- 2026-03-27 19h : **Fix critique du calcul de contexte** — passage de la taille du fichier (faux) aux vrais token counts de l'API Anthropic. Le contexte réel = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` dans `message.usage` du dernier message `assistant` top-level. Filtrage des messages `progress` (sous-agents) qui ont leurs propres compteurs.
- 2026-03-27 18h : Refonte multi-sessions — l'app affiche maintenant UNE ligne par projet actif (le .jsonl le plus récent par dossier projet). Limites de contexte auto-détectées selon le modèle (Opus=1M, Sonnet/Haiku=200K). Notifications indépendantes par projet.
- 2026-03-27 17h : Nouveau logo créé avec Pillow — arc de progression vert→jaune→orange + oeil orange stylisé au centre sur fond bleu nuit. Conversion .icns via iconutil.
- 2026-03-27 : App V1 complète codée et compilée — 4 fichiers Swift, Info.plist, projet Xcode, build OK
- 2026-03-27 : Plan d'action validé — 6 phases définies
- 2026-03-27 : Initialisation du projet, création du dépôt Git et du CONTEXT.md

## Où on en est
L'app est **fonctionnelle et déployée dans /Applications** :
- Surveille en temps réel TOUTES les sessions Claude Code actives (modifiées dans les dernières 48h)
- Affiche le vrai pourcentage de contexte basé sur les token counts API (pas la taille fichier)
- Menu avec code couleur : noms en blanc gras, pourcentages en couleur (vert→jaune→orange→rouge)
- Détecte automatiquement le modèle (Opus 1M, Sonnet 200K, Haiku 200K) et ajuste la limite
- Notifications indépendantes par projet aux seuils 80%, 90%, 100%
- La menu bar affiche le pourcentage de la session la plus critique
- Option+clic sur un item montre les tokens exacts et le nom complet du modèle (calibration)

### Fichiers du projet
```
ContextWatch/
  ContextWatch.xcodeproj/
    project.pbxproj
    project.xcworkspace/
  ContextWatch/
    ContextWatchApp.swift         — point d'entrée @main
    AppDelegate.swift             — NSStatusItem, menu coloré, orchestration
    SessionMonitor.swift          — FSEventStream, scan multi-projets, lecture tokens API
    NotificationManager.swift     — UNUserNotificationCenter, seuils par projet
    Info.plist                    — LSUIElement=true
    AppIcon.icns                  — icône de l'app
generate_icon.py                  — script Python Pillow pour générer le logo
ContextWatch_AppIcon_1024.png     — source PNG du logo (1024x1024)
Exports de app/ContextWatch.app   — build compilé exporté
```

## Architecture et décisions
- **AppKit pur** : pas de SwiftUI, pour compatibilité et contrôle total sur la menu bar
- **LSUIElement = true** : l'app vit exclusivement dans la menu bar, pas d'icône dans le Dock
- **FSEventStream** : surveillance native macOS via `FSEventStreamSetDispatchQueue` (API moderne), latence 1s
- **Tokens réels, pas taille fichier** : on lit les derniers ~100 Ko du .jsonl pour extraire `usage.input_tokens + cache_creation_input_tokens + cache_read_input_tokens` du dernier message `assistant` top-level. C'est le vrai compteur de contexte de l'API Anthropic. On ignore les messages `type: "progress"` qui sont des sous-agents avec leurs propres compteurs.
- **Multi-sessions** : un scan par dossier projet dans `~/.claude/projects/`, on garde le .jsonl le plus récent par projet. Fenêtre d'activité : 48h (constante `activeWindowHours`).
- **Limites auto par modèle** : dictionnaire `contextLimits` dans SessionMonitor — "opus"→1M, "sonnet"→200K, "haiku"→200K. Détection via le champ `message.model` du .jsonl.
- **Non sandboxé** : nécessaire pour accéder à `~/.claude/projects/`
- **Items de menu "enabled" avec action noop** : `isEnabled = false` force macOS à griser le texte, écrasant les attributedTitle colorés. Solution : action `@objc noop()` bidon pour garder les items enabled tout en étant non-interactifs.
- **NSAttributedString pour le menu** : chaque partie de la ligne a ses propres attributs (couleur, police, taille). Noms en blanc gras, pourcentages en couleur+gras, tokens en gris 60% taille 11, modèle en gris 50%.
- **Notifications indépendantes par projet** : `notifiedThresholds: [String: Set<Int>]` indexé par chemin du dossier projet. Reset quand le .jsonl actif change (nouvelle conversation détectée).

## Ce qu'il reste à faire
- [x] Créer la structure du projet Xcode
- [x] Implémenter les 4 fichiers Swift
- [x] Créer Info.plist avec LSUIElement = true
- [x] Tester la compilation
- [x] Créer et intégrer l'icône de l'app
- [x] Refonte multi-sessions (une ligne par projet)
- [x] Fix calcul contexte (tokens réels au lieu de taille fichier)
- [x] Code couleur (vert/jaune/orange/rouge)
- [x] Affichage du modèle (Sonnet/Opus/Haiku)
- [x] Design menu amélioré (attributedTitle, couleurs sélectives)
- [ ] Tester les notifications aux seuils 80/90/100% en conditions réelles
- [ ] Ajouter l'app au Login Items pour lancement automatique au démarrage
- [ ] Éventuellement : option dans le menu pour modifier les limites de tokens manuellement
