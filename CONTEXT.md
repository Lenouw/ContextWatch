# Contexte du projet

## Projet
**ContextWatch** — Application macOS native (menu bar app) qui surveille en temps réel le remplissage du contexte de TOUTES les sessions Claude Code actives simultanément. Elle lit les token counts dans les fichiers .jsonl de `~/.claude/projects/` et alerte l'utilisateur avant que le contexte soit plein pour qu'il puisse sauvegarder à temps.

## Stack technique
- **Langage** : Swift
- **Framework UI** : AppKit (pas de SwiftUI)
- **Target** : macOS 13+
- **Surveillance fichiers** : FSEventStream (natif macOS, pas de polling)
- **Notifications** : UserNotifications (UNUserNotificationCenter)
- **Auto-update** : Sparkle 2.9.0 (SPM) — vérification + téléchargement auto via GitHub Releases
- **Projet** : Xcode project (.xcodeproj)
- **Génération icône** : Python Pillow (script `generate_icon.py`, pas de dépendance runtime)
- **Distribution** : GitHub Releases (Lenouw/ContextWatch) + appcast.xml signé EdDSA

## Dernière mise à jour
2026-03-27 23h45 — Sparkle intégré, indicateurs d'activité, Computer Use, couleurs par catégorie, repo GitHub créé, release v1.1.0

## Ce qu'on a fait
- 2026-03-27 23h45 : **Mise à jour automatique Sparkle** — framework Sparkle 2.9.0 intégré via SPM, clé EdDSA partagée avec ZapClipper (Keychain), SUFeedURL et SUPublicEDKey dans Info.plist, menu "Vérifier les mises à jour…" (⌘U), affichage de la version "ContextWatch v1.1.0 (1)" en bas du menu.
- 2026-03-27 23h30 : **Repo GitHub Lenouw/ContextWatch** créé (public), première release v1.1.0 signée et uploadée, appcast.xml poussé sur main.
- 2026-03-27 23h : **Badge Computer Use 🖥️** — détection des sessions utilisant `mcp__computer-use__*` via un scan des derniers 100 Ko du .jsonl. Affiché en fin de ligne dans le menu.
- 2026-03-27 22h30 : **Indicateurs d'activité** — enum `SessionActivity` (working/waiting/idle) basé sur le dernier message du .jsonl + mtime du fichier. Icônes ⚡💬💤 devant chaque session. En-tête du menu avec décompte par état.
- 2026-03-27 22h : **Couleurs par catégorie de projet** — `colorForProject()` : App→bleu ciel, Site→vert menthe, CRM→orange doux, Screenshot→violet, API/Server→rose, autres→blanc lumineux.
- 2026-03-27 21h : Design du menu amélioré — noms de projets en blanc gras, pourcentages en couleur (vert/jaune/orange/rouge), tokens et modèle en gris. Items "enabled" avec action noop pour éviter le grisage macOS.
- 2026-03-27 20h : Ajout du code couleur dans le menu ET la menu bar — vert (0-60%), jaune (61-79%), orange (80-89%), rouge (90-100%). Affichage du modèle (Sonnet/Opus/Haiku) sur chaque ligne.
- 2026-03-27 19h : **Fix critique du calcul de contexte** — passage de la taille du fichier (faux) aux vrais token counts de l'API Anthropic.
- 2026-03-27 18h : Refonte multi-sessions — une ligne par projet actif, limites auto par modèle, notifications indépendantes.
- 2026-03-27 17h : Nouveau logo créé avec Pillow — arc de progression + oeil orange sur fond bleu nuit.
- 2026-03-27 : App V1 complète codée et compilée — 4 fichiers Swift, build OK
- 2026-03-27 : Initialisation du projet, création du dépôt Git et du CONTEXT.md

## Où on en est
L'app est **complète, déployée dans /Applications, et distribuable** :
- Surveille en temps réel TOUTES les sessions Claude Code actives (fenêtre 48h)
- Affiche le vrai pourcentage de contexte basé sur les token counts API
- Indicateurs d'activité par session : ⚡ en cours (Claude travaille), 💬 en attente (ton tour), 💤 idle
- Badge 🖥️ Computer Use sur les sessions utilisant le contrôle de l'ordinateur
- Noms de projets colorés par catégorie (App→bleu, Site→vert, CRM→orange, Screenshot→violet)
- Pourcentages en couleur (vert→jaune→orange→rouge) selon le remplissage
- Détecte automatiquement le modèle (Opus 1M, Sonnet 200K, Haiku 200K)
- Notifications indépendantes par projet aux seuils 80%, 90%, 100%
- En-tête du menu avec décompte : "8 sessions — ⚡2 💬3"
- **Mise à jour automatique via Sparkle** : "Vérifier les mises à jour…" dans le menu
- Version affichée : "ContextWatch v1.1.0 (1)"
- **Repo GitHub** : https://github.com/Lenouw/ContextWatch — release v1.1.0 signée

### Fichiers du projet
```
ContextWatch/
  ContextWatch.xcodeproj/
    project.pbxproj              — projet Xcode + dépendance Sparkle SPM
  ContextWatch/
    ContextWatchApp.swift         — point d'entrée @main
    AppDelegate.swift             — NSStatusItem, menu coloré, Sparkle updater, orchestration
    SessionMonitor.swift          — FSEventStream, scan multi-projets, tokens API, activité, Computer Use
    NotificationManager.swift     — UNUserNotificationCenter, seuils par projet
    Info.plist                    — LSUIElement=true, SUFeedURL, SUPublicEDKey, version 1.1.0
    AppIcon.icns                  — icône de l'app
appcast.xml                       — feed Sparkle des versions (RSS signé EdDSA)
generate_icon.py                  — script Python Pillow pour générer le logo
ContextWatch_AppIcon_1024.png     — source PNG du logo
```

## Architecture et décisions
- **AppKit pur** : pas de SwiftUI, pour compatibilité et contrôle total sur la menu bar
- **LSUIElement = true** : l'app vit exclusivement dans la menu bar, pas d'icône dans le Dock
- **FSEventStream** : surveillance native macOS, latence 1s
- **Tokens réels** : lecture des derniers ~100 Ko du .jsonl, extraction de `usage.input_tokens + cache_creation_input_tokens + cache_read_input_tokens` du dernier message `assistant` top-level. Filtrage des `progress` (sous-agents).
- **Multi-sessions** : scan par dossier projet dans `~/.claude/projects/`, .jsonl le plus récent par projet. Fenêtre d'activité : 48h.
- **Limites auto par modèle** : dictionnaire `contextLimits` — "opus"→1M, "sonnet"→200K, "haiku"→200K
- **Détection d'activité** : basée sur le `type` + `stop_reason` du dernier message + `mtime` du fichier. Working = tool_use/progress/mtime<30s. Waiting = end_turn + mtime<5min. Idle = end_turn + mtime>5min.
- **Computer Use** : détection par `text.contains("mcp__computer-use__")` dans les derniers 100 Ko du .jsonl
- **Couleurs par catégorie** : `colorForProject()` dans AppDelegate — préfixes "app"→bleu, "site"→vert, "crm"→orange, "screenshot"→violet, "api/server"→rose
- **Items de menu avec action noop** : `isEnabled=false` grise le texte → solution `@objc noop()` pour garder les couleurs
- **Sparkle 2.9.0** : `SPUStandardUpdaterController(startingUpdater: true)` dans AppDelegate. Clé EdDSA partagée avec ZapClipper (même Keychain). Feed via GitHub Raw Content (`appcast.xml` sur main). Distribution via GitHub Releases.
- **Non sandboxé** : nécessaire pour accéder à `~/.claude/projects/` et pour Sparkle (remplacement du binaire)
- **Versionnement** : `MARKETING_VERSION` = 1.1.X (incrémenter le patch à chaque modif), `CURRENT_PROJECT_VERSION` = build number

## Workflow de release
1. Incrémenter `MARKETING_VERSION` (1.1.X+1) et `CURRENT_PROJECT_VERSION` dans `project.pbxproj`
2. Build Release : `xcodebuild -project ... -configuration Release build CONFIGURATION_BUILD_DIR=/tmp/ContextWatch_build`
3. Zipper : `ditto -c -k --sequesterRsrc --keepParent /tmp/ContextWatch_build/ContextWatch.app ContextWatch-X.X.X.zip`
4. Signer : `sign_update ContextWatch-X.X.X.zip` → obtenir `sparkle:edSignature` + `length`
5. Ajouter l'item dans `appcast.xml` (version, signature, URL)
6. Commit + push + `gh release create vX.X.X fichier.zip --title "..." --notes "..."`

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
- [x] Couleurs par catégorie de projet (App, Site, CRM, etc.)
- [x] Indicateurs d'activité (⚡💬💤)
- [x] Badge Computer Use 🖥️
- [x] Mise à jour automatique Sparkle
- [x] Repo GitHub + première release v1.1.0
- [x] Affichage de la version dans le menu
- [ ] Tester les notifications aux seuils 80/90/100% en conditions réelles
- [ ] Ajouter l'app au Login Items pour lancement automatique au démarrage
- [ ] Option dans le menu pour modifier les limites de tokens manuellement
