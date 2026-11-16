// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// DroidNest: one Android game, opened by itself.
///
/// Everything under this is Husk's -- its translation layer, its importer, its JIT, its game screen -- and the app this target
/// builds is a launcher around exactly one of them: the game chosen last. Opening it starts that game full screen; leaving the
/// game (three fingers held for five seconds, or the bar's Close) brings the games back.
///
/// Husk itself is untouched: it has its own target, its own identifier and its own screens (ContentView.swift), and this one
/// compiles from the same sources with `DROIDNEST` defined, which is what leaves its `@main` out.
@main
struct DroidNestApp: App {
    @UIApplicationDelegateAdaptor(HuskAppDelegate.self) private var appDelegate

    init() {
        // Order matters, exactly as in Husk: the log first, because the JIT path is what cannot afford a lost line.
        HuskLog.start()
        HuskLog.logFootprint("droidnest-launch")
        JITBootstrap.noteLaunchState()
        HuskLog.log("droidnest", "debugged at launch: \(JITBootstrap.debuggedAtLaunch); TrollStore: "
                                + "\(JITBootstrap.isInstalledWithTrollStore); jailbroken: \(JITBootstrap.isJailbroken)")
        // Before anything can execute a brk: an unserviced one is a fatal SIGTRAP, not a failed call.
        JITBootstrap.installTrapGuard()
        // Copies of shared APKs that were never placed.
        IncomingFiles.clearLeftovers()
        Task { @MainActor in HuskGamepads.shared.start() }
    }

    var body: some Scene {
        WindowGroup {
            SoloRootView()
                // An APK shared to DroidNest, or opened in it from Files.
                .onOpenURL { url in SoloStore.shared.receive(url) }
        }
    }
}

/// The whole app: the games, and one game over them.
struct SoloRootView: View {
    @ObservedObject private var solo = SoloStore.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var player: TLApp?
    /// One automatic start per launch: a game that failed to open must not be thrown at the screen again and again.
    @State private var autoLaunchDone = false
    /// A game asked for while JIT was still coming on: started as soon as the debugger has attached.
    @State private var waiting: String?

    var body: some View {
        SoloManagerView(onPlay: play)
            .fullScreenCover(item: $player, onDismiss: { solo.refresh() }) { app in
                SoloPlayer(app: app) { player = nil }
            }
            .onAppear(perform: launch)
            // The built-in helper attaches while DroidNest is in the foreground, so this is the moment the region can be
            // claimed and the game that was waiting on it can start.
            .onChange(of: jit.attachGeneration) { _ in attached() }
    }

    // MARK: opening the chosen game

    private func launch() {
        guard !autoLaunchDone else { return }
        autoLaunchDone = true
        solo.refresh()
        SoloJIT.turnOnAtLaunchIfPossible()
        openChosenGame()
    }

    private func attached() {
        _ = JITBootstrap.prewarm()
        if let id = waiting, let app = solo.app(id) {
            waiting = nil
            start(app)
        } else {
            openChosenGame()
        }
    }

    /// The game chosen last, if there is one and it can actually run.
    private func openChosenGame() {
        guard player == nil else { return }
        switch SoloLaunch.plan(primary: solo.primary, installed: solo.entries) {
        case .play(let game):
            guard let app = solo.app(game.id) else {
                solo.launchIssue = .chosenGameRemoved(label: game.label)
                return
            }
            if SoloJIT.readyOrJITLess { start(app) } else { waiting = app.id }
        case .choose(let issue):
            // Nothing chosen: the games, with the reason at the top.
            solo.launchIssue = issue
        }
    }

    /// A game was tapped: it becomes the game DroidNest opens, and it opens now.
    private func play(_ app: TLApp) {
        solo.setPrimary(app)
        start(app)
    }

    private func start(_ app: TLApp) {
        guard SoloJIT.readyOrJITLess else {
            waiting = app.id
            SoloJIT.turnOn()
            return
        }
        if let running = solo.loadedGameBlocking(app) {
            solo.conflict = SoloSessionConflict(running: running, wantedID: app.id, wantedLabel: app.label)
            return
        }
        player = app
    }
}

/// What DroidNest tells iOS about itself, for the one line of the footer.
enum SoloAbout {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// The name is fixed: iOS has no supported way for an app to rename itself, so the Home Screen says DroidNest whatever
    /// game is chosen. The game's own name and icon are shown in the app, where iOS does let an app draw them.
    static let nameNote = "On the Home Screen DroidNest keeps its own name and icon: iOS does not let an app rename itself or "
        + "adopt another app's icon. The game you chose is named and drawn here, and it is what opens."
}
