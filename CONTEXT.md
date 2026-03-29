# Contexte du projet

## Projet
**ContextWatch** — Application macOS native (menu bar app) qui surveille en temps réel le remplissage du contexte de TOUTES les sessions Claude Code actives simultanément. Elle lit les token counts dans les fichiers .jsonl de `~/.claude/projects/` et alerte l'utilisateur avant que le contexte soit plein pour qu'il puisse sauvegarder à temps. Elle détecte aussi les limites d'images pour éviter les crashs de session.

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
2026-03-29 21h — v1.3.2 : audit sécurité, fix couleurs

## Ce qu'on a fait
- 2026-03-29 21h : **Audit sécurité + fix couleurs v1.3.2** — 8 vulnérabilités corrigées : cap mémoire 50MB countImages (HIGH), sanitisation displayName dans notifications (MEDIUM), suppression TOCTOU openProjectsFolder (MEDIUM), logging JSON errors via os_log (MEDIUM), suppression force-unwrap NotificationManager (LOW), FSEventStream passRetained + retain/release callbacks (LOW), cap imageCount display 9999 (LOW), print → os_log (INFO).
- 2026-03-29 20h47 : **Fix couleurs illisibles v1.3.2** — jaune 61-79% → ambre foncé, fallback projets doré → gris argenté.
- 2026-03-28 10h : **Détection intelligente dimensions images** — lecture des headers PNG (octets 16-23) pour dimensions exactes, estimation JPEG via taille base64. Alerte uniquement si > 20 images ET au moins une > 2000px. Pas de fausse alerte si toutes les images sont petites. Release v1.3.1.
- 2026-03-28 09h30 : **Compteur d'images par session** — scan du .jsonl entier pour compter les blocs `"type":"image"`. Affichage 📷N / ⚠️N / 🚨N dans le menu. Notifications à 16 et 21 images (une seule fois par seuil). Release v1.3.0.
- 2026-03-28 09h : **Fix messages `<synthetic>`** — les messages post-crash (model: `<synthetic>`, 0 tokens) sont maintenant ignorés lors de l'extraction des tokens. Plus de retombée à 0% après un crash de session.
- 2026-03-28 08h : **Couleurs plus vives** — couleurs de catégories saturées (bleu vif, vert franc, orange vif, violet), catégorie "Scan" ajoutée, fallback doré au lieu de blanc. Release v1.2.1.
- 2026-03-28 07h45 : **Release v1.2.0** — première release avec indicateurs d'activité, Computer Use, couleurs par catégorie, tri par activité.
- 2026-03-28 02h : **Tri par activité** — sessions triées working > waiting > idle, puis par date décroissante.
- 2026-03-28 01h : **Clic session → focus Claude Desktop** — `NSRunningApplication.activate()`. Exploration approfondie du deep linking (`claude://resume`, `claude://claude.ai/chat/`) — aucune solution viable pour cibler un onglet spécifique. Limitation Anthropic (issues #18818, #28147, #34097).
- 2026-03-28 00h : **Champ `cwd` dans SessionInfo** — extrait du .jsonl pour matcher avec les fichiers de session Claude Desktop.
- 2026-03-27 23h45 : **Mise à jour automatique Sparkle** — Sparkle 2.9.0 via SPM, clé EdDSA, menu "Vérifier les mises à jour…", version affichée.
- 2026-03-27 23h30 : **Repo GitHub Lenouw/ContextWatch** créé, release v1.1.0.
- 2026-03-27 23h : **Badge Computer Use 🖥️**, **Indicateurs d'activité ⚡💬💤**, **Couleurs par catégorie**.
- 2026-03-27 21h : Design menu amélioré, code couleur, modèle affiché.
- 2026-03-27 19h : Fix critique calcul contexte (tokens réels API).
- 2026-03-27 18h : Refonte multi-sessions.
- 2026-03-27 : App V1 + initialisation projet.

## Où on en est
L'app est **complète, déployée (v1.3.1), et distribuable via Sparkle** :
- Surveille en temps réel TOUTES les sessions Claude Code actives (fenêtre 48h)
- Affiche le vrai pourcentage de contexte basé sur les token counts API (fix synthetic inclus)
- **Compteur d'images intelligent** : détecte les dimensions réelles (PNG headers, estimation JPEG), alerte seulement si > 20 images ET au moins une > 2000px
- Indicateurs d'activité : ⚡ en cours, 💬 en attente, 💤 idle
- Badge 🖥️ Computer Use
- Noms de projets colorés par catégorie (App→bleu, Site→vert, CRM→orange, Scan→violet)
- Tri par activité (working en haut, idle en bas)
- Clic sur session → focus Claude Desktop
- Notifications tokens (80%, 90%, 100%) + notifications images (16 et 21 si grande image)
- Mise à jour automatique Sparkle — v1.3.1 publiée sur GitHub
- **Repo** : https://github.com/Lenouw/ContextWatch

### Fichiers du projet
```
ContextWatch/
  ContextWatch.xcodeproj/
    project.pbxproj              — projet Xcode + Sparkle SPM, version 1.3.1 (build 5)
  ContextWatch/
    ContextWatchApp.swift         — point d'entrée @main
    AppDelegate.swift             — menu coloré, Sparkle, clic session, compteur images
    SessionMonitor.swift          — FSEventStream, tokens API, activité, Computer Use, cwd, images
    NotificationManager.swift     — seuils contexte + alertes images intelligentes
    Info.plist                    — LSUIElement, SUFeedURL, SUPublicEDKey
    AppIcon.icns                  — icône
appcast.xml                       — feed Sparkle (v1.1.0 → v1.3.1)
generate_icon.py                  — script Pillow pour le logo
```

## Architecture et décisions
- **Tokens réels** : `input_tokens + cache_creation + cache_read` du dernier assistant non-synthetic
- **Messages `<synthetic>` ignorés** : Claude écrit des messages avec `model: "<synthetic>"` quand une session crashe → 0 tokens. On les skip dans l'extraction de tokens ET dans la détection d'activité.
- **Compteur d'images** : scan complet du .jsonl, compte les blocs `"type":"image"` dans les messages user/assistant (pas les `toolUseResult` qui sont des doublons JSONL). Détection des dimensions via header PNG (octets 16-23 = width/height big-endian) ou estimation taille JPEG (base64 > 400K chars ≈ > 2000px).
- **Règle des 20 images** (doc Anthropic) : ≤ 20 images = limite 8000px/image, > 20 images = limite 2000px/image. Si une image > 2000px est dans la conversation et qu'on dépasse 20 images, la session crashe de façon irréversible.
- **Notifications images** : une seule par seuil (15 et 20), stockées dans le même Set que les seuils de contexte avec des valeurs distinctes (1015, 1020). Déclenchées uniquement si `hasLargeImage == true`.
- **Tri par activité** : working (prio 0) > waiting (prio 1) > idle (prio 2), puis par date décroissante.
- **Navigation onglet impossible** : Claude Desktop (Electron) n'expose ni raccourcis clavier ni deep link de navigation. `claude://resume` crée un nouvel onglet. Issues #18818, #28147, #34097 — "Not Planned".
- **Sparkle 2.9.0** : clé EdDSA partagée avec ZapClipper. Feed via GitHub Raw Content.

## Workflow de release
1. Incrémenter `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans `project.pbxproj`
2. `xcodebuild -project ... -configuration Release build CONFIGURATION_BUILD_DIR=/tmp/ContextWatch_build`
3. `ditto -c -k --sequesterRsrc --keepParent /tmp/ContextWatch_build/ContextWatch.app ContextWatch-X.X.X.zip`
4. `sign_update ContextWatch-X.X.X.zip` → `sparkle:edSignature` + `length`
5. Ajouter l'item dans `appcast.xml`
6. `git add -A && git commit && git push`
7. `gh release create vX.X.X fichier.zip --title "..." --notes "..."`
8. Déployer localement : `killall → rm → cp → open`

## Problèmes connus
- **Navigation onglet Claude Desktop impossible** : pas de deep link, pas de raccourci clavier, pas d'API
- **Estimation JPEG imprécise** : sans parser les markers SOF du JPEG, on estime la taille via la longueur du base64 (seuil 400K chars). Peut avoir des faux négatifs sur des JPEG très compressés mais larges.
- **Scan complet du .jsonl pour les images** : on lit le fichier entier à chaque cycle (peut être lent pour les très gros fichiers > 10Mo). Un cache serait souhaitable.

## Ce qu'il reste à faire
- [x] Toutes les features de base (multi-sessions, tokens, couleurs, activité, Computer Use, Sparkle)
- [x] Compteur d'images intelligent avec détection dimensions
- [x] Fix messages synthetic
- [x] Tri par activité
- [x] Clic session → focus Claude Desktop
- [x] Releases v1.1.0 → v1.3.1 publiées
- [ ] Tester les notifications de tokens aux seuils 80/90/100% en conditions réelles
- [ ] Ajouter l'app au Login Items pour lancement automatique au démarrage
- [ ] Cache pour le comptage d'images (éviter de relire le fichier entier à chaque scan)
- [ ] Option dans le menu pour modifier les limites de tokens manuellement
