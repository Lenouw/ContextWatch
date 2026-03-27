import Cocoa

/// Point d'entrée de l'application ContextWatch.
/// Menu bar app qui surveille le remplissage du contexte Claude Code.
@main
struct ContextWatchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
