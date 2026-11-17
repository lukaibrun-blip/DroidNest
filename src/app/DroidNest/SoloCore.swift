// SPDX-License-Identifier: GPL-2.0-or-later
//
// DroidNest's decisions, with nothing of UIKit, SwiftUI or the file system in them, so they can be run and checked on a Mac:
// tests/solo/run.sh compiles this file with tests/solo/solo_core_test.swift and runs it.
//
// Everything here answers one of four questions: which game DroidNest opens when it starts, what it remembers about your
// choice, what it will and will not import, and when three fingers held down mean "back to your games".
import Foundation

// MARK: - the game DroidNest opens by itself

/// The one game DroidNest starts when it is opened.
///
/// The name is kept beside the folder so a game whose APK has gone can still be named when it cannot be opened -- "Geometry
/// Dash's files are gone from DroidNest" reads better than an identifier.
struct SoloPrimaryGame: Codable, Equatable {
    /// The app's own folder in Documents/TranslationLayer.
    var id: String
    /// What the library called it when it was chosen.
    var label: String
    /// Its Android package name, when the APK's manifest gave one.
    var packageName: String?

    init(id: String, label: String, packageName: String? = nil) {
        self.id = id
        self.label = label
        self.packageName = packageName
    }
}

/// One game as the library holds it: only what the choice needs to be made against.
struct SoloLibraryEntry: Equatable {
    var id: String
    var label: String
    var packageName: String?
    /// Whether the APK's own report says its code can run here at all. An APK nobody could read is left to be tried.
    var runnable: Bool
}

/// Why the games are on screen instead of a game.
enum SoloLaunchIssue: Equatable {
    case nothingChosen
    case chosenGameRemoved(label: String)
    case chosenGameCannotRun(label: String)

    /// Said where the library is, in words that name the next step.
    var message: String {
        switch self {
        case .nothingChosen:
            return "Pick the game DroidNest should open. It starts by itself the next time you open DroidNest."
        case .chosenGameRemoved(let label):
            return "\(label) is no longer in DroidNest -- its APK was removed, or the folder it was kept in is gone. "
                 + "Choose another game, or add it again with +."
        case .chosenGameCannotRun(let label):
            return "\(label) has no ARM code DroidNest can run, so it would not start. Choose another game, or tap it to try anyway."
        }
    }
}

/// What opening DroidNest should do.
enum SoloLaunchPlan: Equatable {
    case play(SoloPrimaryGame)
    case choose(SoloLaunchIssue)
}

enum SoloLaunch {
    /// The game to start, decided against what is on disk now rather than what was remembered: an APK can be removed in
    /// Files, a folder can be left behind half-copied, and a game that was readable last month may not be.
    static func plan(primary: SoloPrimaryGame?, installed: [SoloLibraryEntry]) -> SoloLaunchPlan {
        guard let primary else { return .choose(.nothingChosen) }
        guard let entry = installed.first(where: { $0.id == primary.id }) else {
            return .choose(.chosenGameRemoved(label: primary.label))
        }
        guard entry.runnable else { return .choose(.chosenGameCannotRun(label: entry.label)) }
        // The library's own reading, not the remembered one: a game renamed since it was chosen says its new name.
        return .play(SoloPrimaryGame(id: entry.id, label: entry.label, packageName: entry.packageName))
    }
}

// MARK: - remembering the choice

/// The chosen game, written where it survives being closed, force-quit or restarted.
///
/// UserDefaults holds it rather than a file of its own: it is one small value, and it is read before anything else at launch.
/// `defaults` is a parameter so the checks in tests/solo can use a throwaway suite instead of the app's own.
struct SoloSelectionStore {
    static let key = "droidnest.primaryGame"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> SoloPrimaryGame? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(SoloPrimaryGame.self, from: data)
    }

    /// nil forgets the choice, which is what removing the chosen game does.
    func save(_ game: SoloPrimaryGame?) {
        guard let game, let data = try? JSONEncoder().encode(game) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - importing

/// The one thing left in Swift about importing: how a size is written. What is accepted, and why a file is refused, is
/// decided by DroidNest's Rust core (src/droidnest-core, through DNCore) -- before a byte is copied.
enum SoloImport {
    /// "1.2 GB", for a sentence about space.
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }
}

// MARK: - three fingers, held

/// Three fingers held down on the game screen: the way back to the games without a button left over a game.
///
/// It is meant to be impossible to do by accident. Exactly three fingers have to be down -- a fourth joining, or one lifting,
/// ends the attempt -- and they have to stay down for five seconds. A game that asks for three fingers at once (a chord, a
/// three-player mode) therefore cannot trip it, and the app asks before it leaves anyway.
///
/// This is the decision only. The recognizer in ThreeFingerHold.swift feeds it what the screen reports and draws its answer.
struct ThreeFingerHold {
    enum Phase: Equatable {
        /// No fingers, or not the right number of them.
        case idle
        /// The right number of fingers, down for `progress` of the way.
        case holding(progress: Double)
        /// Held long enough: the way out has been asked for.
        case reached
        /// It was started and then broken off (a finger lifted, or another arrived).
        case cancelled
    }

    static let fingers = 3
    static let duration: TimeInterval = 5

    let requiredFingers: Int
    let hold: TimeInterval

    private var startedAt: TimeInterval?
    private(set) var phase: Phase = .idle

    init(fingers: Int = ThreeFingerHold.fingers, duration: TimeInterval = ThreeFingerHold.duration) {
        requiredFingers = max(fingers, 1)
        hold = max(duration, 0.1)
    }

    /// The number of fingers on the screen changed, because one arrived or left.
    mutating func fingersChanged(to count: Int, at now: TimeInterval) -> Phase {
        guard count == requiredFingers else {
            // Anything but the right number breaks it: three fingers and a thumb resting on the glass is not the gesture.
            let wasHold = startedAt != nil
            startedAt = nil
            phase = wasHold ? .cancelled : .idle
            return phase
        }
        if startedAt == nil {
            startedAt = now
            phase = .holding(progress: 0)
        }
        return phase
    }

    /// The clock moved: how far through the hold it is, or that it is over.
    mutating func tick(at now: TimeInterval) -> Phase {
        guard let startedAt else {
            if phase == .reached { return .reached }
            phase = .idle
            return phase
        }
        let elapsed = now - startedAt
        if elapsed >= hold {
            phase = .reached
            return phase
        }
        phase = .holding(progress: min(max(elapsed / hold, 0), 1))
        return phase
    }

    /// Start over: the same gesture can be made again later in the session.
    mutating func reset() {
        startedAt = nil
        phase = .idle
    }

    /// Whether a boring tap is in progress rather than the way out.
    var isHolding: Bool {
        if case .holding = phase { return true }
        return false
    }
}

/// Where the gesture's setting is kept.
enum SoloGesture {
    /// On unless the user turns it off, for a game that wants three fingers of its own.
    static let exitKey = "droidnest.exitGesture"
}

/// The other switches, kept here rather than in the type that uses them: a `@AppStorage` reads its key while a view is being
/// built, which is outside the main actor the rest of the app is written on.
enum SoloSettings {
    /// "Turn JIT on when DroidNest opens", on by default.
    static let autoJITKey = "droidnest.jit.autoEnable"
    /// "Keep the game running when you go back", on by default: a game that stops drawing when the app leaves the screen
    /// usually comes back to a black frame, which reads as a crash.
    static let keepRunningKey = "droidnest.keepRunning"
}

// MARK: - which game the runtime can hold

/// What a session of DroidNest already has loaded, and what starting another game would need.
///
/// The native runtime loads one game's libraries into the process and does not let go: Husk answers this by closing itself and
/// opening the other game on the next launch, and DroidNest does the same, with a button rather than a surprise.
struct SoloSessionConflict: Equatable {
    /// What is loaded now, by name ("Subway Surfers", or "another game" when the library no longer knows it).
    var running: String
    /// The game that was asked for, and is now the one DroidNest opens.
    var wantedID: String
    var wantedLabel: String

    var message: String {
        "\(running) is still loaded, and only one game can run each time DroidNest opens. \(wantedLabel) is now the game DroidNest "
        + "opens, so it starts as soon as DroidNest is closed and opened again."
    }
}
