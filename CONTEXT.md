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
2026-03-28 01h — Clic session ouvre Claude Desktop, exploration deep link (limitation Anthropic)

## Ce qu'on a fait
- 2026-03-28 01h : **Clic sur session → ouvre Claude Desktop** — cliquer sur une session dans le menu amène Claude Desktop au premier plan. Exploration approfondie du deep linking (`claude://resume`, `claude://claude.ai/chat/`) et de l'Accessibility API (AXUIElement, AXManualAccessibility). Conclusion : **Claude Desktop ne supporte pas la navigation vers un onglet spécifique** depuis l'extérieur — marqué "Not Planned" par Anthropic (issues #18818, #28147, #34097). Le `claude://resume?session=X&cwd=Y` crée un nouvel onglet au lieu de naviguer, et renomme la session. On garde le comportement safe : juste focus Claude.
- 2026-03-28 00h : **Ajout du champ `cwd` à SessionInfo** — extrait depuis les lignes du .jsonl, permet de matcher avec les fichiers de session Claude Desktop dans `~/Library/Application Support/Claude/claude-code-sessions/`.
- 2026-03-27 23h45 : **Mise à jour automatique Sparkle** — framework Sparkle 2.9.0 intégré via SPM, clé EdDSA partagée avec ZapClipper (Keychain), SUFeedURL et SUPublicEDKey dans Info.plist, menu "Vérifier les mises à jour…" (⌘U), affichage de la version "ContextWatch v1.1.0 (1)" en bas du menu.
- 2026-03-27 23h30 : **Repo GitHub Lenouw/ContextWatch** créé (public), première release v1.1.0 signée et uploadée, appcast.xml poussé sur main.
- 2026-03-27 23h : **Badge Computer Use 🖥️** — détection des sessions utilisant `mcp__computer-use__*` via un scan des derniers 100 Ko du .jsonl.
- 2026-03-27 22h30 : **Indicateurs d'activité** — enum `SessionActivity` (working/waiting/idle). Icônes ⚡💬💤.
- 2026-03-27 22h : **Couleurs par catégorie de projet** — App→bleu, Site→vert, CRM→orange, Screenshot→violet.
- 2026-03-27 21h : Design du menu amélioré — noms colorés, pourcentages en couleur, tokens et modèle en gris.
- 2026-03-27 20h : Code couleur vert/jaune/orange/rouge + affichage modèle.
- 2026-03-27 19h : Fix critique calcul contexte — tokens réels API.
- 2026-03-27 18h : Refonte multi-sessions.
- 2026-03-27 17h : Nouveau logo Pillow.
- 2026-03-27 : App V1 + initialisation projet.

## Où on en est
L'app est **complète, déployée dans /Applications, et distribuable** :
- Surveille en temps réel TOUTES les sessions Claude Code actives (fenêtre 48h)
- Affiche le vrai pourcentage de contexte basé sur les token counts API
- Indicateurs d'activité : ⚡ en cours, 💬 en attente, 💤 idle
- Badge 🖥️ Computer Use
- Noms de projets colorés par catégorie (App→bleu, Site→vert, CRM→orange, Screenshot→violet)
- Pourcentages en couleur (vert→jaune→orange→rouge)
- Détecte le modèle (Opus 1M, Sonnet 200K, Haiku 200K)
- Notifications indépendantes par projet aux seuils 80%, 90%, 100%
- **Clic sur session → focus Claude Desktop** (navigation vers l'onglet spécifique pas possible actuellement)
- Mise à jour automatique via Sparkle
- Version affichée : "ContextWatch v1.1.0 (1)"
- **Repo GitHub** : https://github.com/Lenouw/ContextWatch — release v1.1.0

### Fichiers du projet
```
ContextWatch/
  ContextWatch.xcodeproj/
    project.pbxproj              — projet Xcode + dépendance Sparkle SPM
  ContextWatch/
    ContextWatchApp.swift         — point d'entrée @main
    AppDelegate.swift             — NSStatusItem, menu coloré, Sparkle, clic→focus Claude
    SessionMonitor.swift          — FSEventStream, scan multi-projets, tokens API, activité, Computer Use, cwd
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
- **Détection d'activité** : basée sur le `type` + `stop_reason` du dernier message + `mtime` du fichier.
- **Computer Use** : détection par `text.contains("mcp__computer-use__")` dans les derniers 100 Ko
- **Couleurs par catégorie** : `colorForProject()` — préfixes "app"→bleu, "site"→vert, "crm"→orange, "screenshot"→violet
- **Sparkle 2.9.0** : `SPUStandardUpdaterController(startingUpdater: true)`. Clé EdDSA partagée. Feed via GitHub Raw Content.
- **Non sandboxé** : nécessaire pour `~/.claude/projects/` et Sparkle
- **Clic session → focus Claude** : `NSRunningApplication.activate()`. La navigation vers un onglet spécifique n'est PAS possible — Claude Desktop (Electron) n'expose ni raccourcis clavier ni deep link de navigation. `claude://resume` crée un nouvel onglet. Issues GitHub #18818, #28147, #34097 demandent cette feature mais elle est "Not Planned" par Anthropic.
- **champ `cwd` dans SessionInfo** : extrait du .jsonl, correspond au répertoire de travail réel du projet

## Workflow de release
1. Incrémenter `MARKETING_VERSION` (1.1.X+1) et `CURRENT_PROJECT_VERSION` dans `project.pbxproj`
2. Build Release : `xcodebuild -project ... -configuration Release build CONFIGURATION_BUILD_DIR=/tmp/ContextWatch_build`
3. Zipper : `ditto -c -k --sequesterRsrc --keepParent /tmp/ContextWatch_build/ContextWatch.app ContextWatch-X.X.X.zip`
4. Signer : `sign_update ContextWatch-X.X.X.zip` → obtenir `sparkle:edSignature` + `length`
5. Ajouter l'item dans `appcast.xml` (version, signature, URL)
6. Commit + push + `gh release create vX.X.X fichier.zip --title "..." --notes "..."`

## Problèmes connus
- **Navigation onglet Claude Desktop impossible** : pas de deep link, pas de raccourci clavier, pas d'API. `claude://resume?session=X&cwd=Y` crée un nouvel onglet et renomme la session existante. `claude://claude.ai/chat/<uuid>` fait bugger l'app. Seule solution viable : focus l'app, l'utilisateur clique manuellement sur l'onglet.

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
- [x] Clic session → focus Claude Desktop
- [ ] Navigation vers l'onglet spécifique (bloqué — attendre qu'Anthropic implémente)
- [ ] Tester les notifications aux seuils 80/90/100% en conditions réelles
- [ ] Ajouter l'app au Login Items pour lancement automatique au démarrage
- [ ] Option dans le menu pour modifier les limites de tokens manuellement
