// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import SwiftUI

/// DroidNest's side of the library: which game is the main one, what an import is doing, and what is loaded in this run.
///
/// The games themselves are Husk's. `TranslationLayerStore` is the one place that copies an APK into the app's own storage,
/// reads the name and icon out of it and keeps its report, and it already survives being closed and restarted; this adds the
/// one thing a launcher needs on top -- the choice of the game to open -- and nothing that deletes anything without being
/// asked to.
@MainActor
final class SoloStore: ObservableObject {
    static let shared = SoloStore()

    private let library = TranslationLayerStore.shared
    private let selection = SoloSelectionStore()

    /// The game DroidNest opens when it starts.
    @Published private(set) var primary: SoloPrimaryGame?
    /// What the games say when they were opened instead of the game that should have started.
    @Published var launchIssue: SoloLaunchIssue?
    /// An import, a copy or a game that cannot start, said in one sentence over the library.
    @Published var error: String?
    /// The file being copied, by name, while it is being copied.
    @Published private(set) var importing: String?
    /// A game that was asked for while another one is still loaded in this process.
    @Published var conflict: SoloSessionConflict?

    private init() { primary = selection.load() }

    var apps: [TLApp] { library.apps }

    var primaryApp: TLApp? { app(primary?.id) }

    func app(_ id: String?) -> TLApp? {
        guard let id else { return nil }
        return library.apps.first { $0.id == id }
    }

    /// Everything the launch decision is made against.
    var entries: [SoloLibraryEntry] {
        library.apps.map {
            SoloLibraryEntry(id: $0.id, label: $0.label, packageName: $0.packageName, runnable: Self.runnable($0))
        }
    }

    /// An APK nobody could read is left to be tried; one whose report says its code cannot run here is not.
    static func runnable(_ app: TLApp) -> Bool { app.report?.canRun ?? true }

    func refresh() { library.reload() }

    // MARK: choosing

    /// Tapping a game makes it the one DroidNest opens, which is the whole of "the main game".
    func setPrimary(_ app: TLApp) {
        primary = SoloPrimaryGame(id: app.id, label: app.label, packageName: app.packageName)
        selection.save(primary)
        if launchIssue != nil { launchIssue = nil }
    }

    /// Closing DroidNest so the game that was just chosen is the one that can load. Only a relaunch frees the libraries the
    /// runtime has already loaded, so this is the only way to switch mid-session without pretending otherwise.
    func restartIntoWantedGame() {
        guard let conflict, let wanted = app(conflict.wantedID) else { return }
        setPrimary(wanted)
        self.conflict = nil
        CrashReport.gameEnded()
        HuskLog.flushNow()
        exit(0)
    }

    /// What is loaded in this run of DroidNest, if it is not `app`.
    ///
    /// The native runtime holds one game's libraries in the process and does not let go: Husk answers this by closing itself
    /// and opening the other game on the next launch, and DroidNest says so rather than failing at the first frame.
    func loadedGameBlocking(_ app: TLApp) -> String? {
        guard let loaded = husk_native_loaded_apk().map({ String(cString: $0) }) else { return nil }
        if loaded == app.apks.first { return nil }
        if loaded.hasPrefix("ps4:") { return "a PS4 game" }
        if let other = library.apps.first(where: { $0.apks.first == loaded }) { return other.label }
        return "another game"
    }

    // MARK: importing

    /// An APK shared to DroidNest, or opened in it from Files.
    func receive(_ url: URL) { importFiles([url]) }

    /// Copy the chosen files in, then read them. Nothing is deleted, here or on a failure: a file that could not be read is
    /// kept and named, so it can be looked at rather than silently disappearing.
    func importFiles(_ urls: [URL]) {
        guard importing == nil else { return }
        let files = urls.map { (name: $0.lastPathComponent, bytes: Self.bytes(of: $0)) }
        if let rejection = SoloImport.rejection(for: files, free: Self.freeBytes()) {
            error = rejection.message
            return
        }
        let before = Set(library.apps.map(\.id))
        importing = files.count == 1 ? files[0].name : "\(files.count) files"
        library.add(urls)
        Task { @MainActor in
            // TranslationLayerStore copies and scans away from the main thread and says it is done by clearing `busy`.
            while library.busy != nil { try? await Task.sleep(nanoseconds: 150_000_000) }
            importing = nil
            if let failure = library.lastError {
                library.lastError = nil
                error = failure
                return
            }
            let added = library.apps.filter { !before.contains($0.id) }
            guard let first = added.first else {
                error = "That file was not added to DroidNest."
                return
            }
            if primary == nil { setPrimary(first) }
            if added.count == 1 { checkReadable(first) }
        }
    }

    /// An APK that was copied but read as nothing: said once, and the file kept.
    private func checkReadable(_ app: TLApp) {
        guard app.report == nil || app.report?.ok == false else { return }
        error = "DroidNest added \(app.label), but could not read its APK as an Android app, so it may not start. "
              + "The file is still there: remove it from the list if it was the wrong one."
    }

    // MARK: removing

    /// Deleting a game, which is the only thing here that removes an APK, and only when it is asked for by name.
    func remove(_ app: TLApp) {
        if primary?.id == app.id {
            primary = nil
            selection.save(nil)
        }
        library.remove(app)
    }

    // MARK: the phone's side

    /// Space an APK's copy has to fit in, counting what iOS says can still be written.
    static func freeBytes() -> Int64 {
        let url = TranslationLayer.root
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return free
    }

    static func bytes(of url: URL) -> Int64 {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size ?? 0
    }
}

// MARK: - JIT

/// Turning JIT on, without asking anyone to open another app first.
///
/// A game's own ARM code has to run from memory it can write and then execute, and iOS only gives an app that memory through a
/// debugger. Husk has five ways to get one; DroidNest asks for the unattended ones itself as it opens:
///
/// - **Built-in StikJIT** (iOS 26 and later): Husk's own helper extension in `PlugIns/` attaches to DroidNest while it stays in
///   the foreground. Nothing to open, nothing to tap -- but it needs the pairing file and LocalDevVPN, which are set up once, by
///   hand, in the walkthrough this shows when they are missing.
/// - **TrollStore** (a copy installed through it): TrollStore attaches for a moment as the app opens, with no tap.
/// - **A jailbreak** (Dopamine's Allow JIT in Apps): iOS marks apps debugged as they start.
/// - **JIT-less mode**: with the certificate that installed DroidNest imported, a game's libraries are converted to signed
///   dylibs once and then need no executable memory at all.
/// - **StikDebug**, a separate app, is what iOS 15 to 26 users without TrollStore or a jailbreak fall back to: for that one,
///   iOS has no way for DroidNest to attach a debugger by itself, so the hand-off opens StikDebug and comes back.
///
/// Nothing here claims more than that. Where none of it applies, the games say so and stay shut.
@MainActor
enum SoloJIT {
    /// On by default: DroidNest's whole point is opening a game without a step in front of it.
    static var autoEnable: Bool {
        UserDefaults.standard.object(forKey: SoloSettings.autoJITKey) as? Bool ?? true
    }

    /// True when a game can be started now, with JIT or without it.
    static var readyOrJITLess: Bool { JITBootstrap.ready || JITLess.enabled }

    /// The unattended turn-on, once per launch. Says nothing on screen: the library shows the state, and the JIT card is what
    /// offers the walkthrough when something is missing.
    static func turnOnAtLaunchIfPossible() {
        guard !JITBootstrap.ready else {
            // Already debugged (TrollStore, a jailbreak, or a debugger that attached before us). Claim the region while
            // whoever attached is still there; after the first call this is free.
            JITBootstrap.prewarm()
            return
        }
        let jit = JITCoordinator.shared
        if JITBootstrap.isInstalledWithTrollStore {
            HuskLog.log("droidnest", "installed through TrollStore: asking it for JIT as DroidNest opens")
            jit.enableAtLaunchIfAsked()
            return
        }
        guard autoEnable, HuskBuiltInJIT.isAvailable, jit.hasPairing else { return }
        HuskLog.log("droidnest", "turning JIT on with the built-in StikJIT helper")
        jit.method = .builtIn
        jit.enable()
    }

    /// The button, for when something was missing at launch and has since been set up.
    static func turnOn() {
        guard !JITBootstrap.ready else { return }
        let jit = JITCoordinator.shared
        if JITBootstrap.isInstalledWithTrollStore { jit.method = .trollStore }
        else if HuskBuiltInJIT.isAvailable, jit.hasPairing { jit.method = .builtIn }
        jit.enable()
    }

    /// One line for the library: whether a game can start, and what is missing if not.
    static var summary: String {
        if JITBootstrap.ready { return "JIT is on." }
        if JITLess.enabled { return "JIT is off, but JIT-less mode is on: games run from signed dylibs." }
        guard let failure = JITCoordinator.shared.error else { return "JIT is off, so no game can start yet." }
        return failure
    }
}
