// SPDX-License-Identifier: GPL-2.0-or-later
// The checks `run.sh` runs: DroidNest's decisions about which game to open, what it remembers, what it will not import, and
// when three fingers held down mean "back to your games". No UIKit, no simulator, no iPhone: a Mac with Xcode's toolchain is
// enough (tests/solo/run.sh).
import Foundation

var failures = 0
var checks = 0

func check(_ what: String, _ ok: Bool) {
    checks += 1
    if !ok {
        failures += 1
        print("  FAIL  \(what)")
    }
}

func equal<T: Equatable>(_ what: String, _ got: T, _ want: T) {
    checks += 1
    if got != want {
        failures += 1
        print("  FAIL  \(what)\n        got  \(got)\n        want \(want)")
    }
}

func section(_ title: String) { print("- \(title)") }

// MARK: - which game opens

section("the game that opens when DroidNest starts")

let geometryDash = SoloLibraryEntry(id: "A", label: "Geometry Dash", packageName: "com.robtopx.geometryjump", runnable: true)
let subway = SoloLibraryEntry(id: "B", label: "Subway Surfers", packageName: "com.kiloo.subwaysurf", runnable: true)

equal("nothing chosen shows the games", SoloLaunch.plan(primary: nil, installed: [geometryDash, subway]),
      .choose(.nothingChosen))

equal("nothing chosen with no games still shows the games",
      SoloLaunch.plan(primary: nil, installed: []), .choose(.nothingChosen))

equal("the chosen game opens",
      SoloLaunch.plan(primary: SoloPrimaryGame(id: "B", label: "Subway Surfers"), installed: [geometryDash, subway]),
      .play(SoloPrimaryGame(id: "B", label: "Subway Surfers", packageName: "com.kiloo.subwaysurf")))

// The remembered label is the one from when it was chosen; a rename in the library has to show.
equal("a renamed game opens under its new name",
      SoloLaunch.plan(primary: SoloPrimaryGame(id: "B", label: "Subway Surfers", packageName: "com.kiloo.subwaysurf"),
                      installed: [SoloLibraryEntry(id: "B", label: "Subway Surfers 2", packageName: "com.kiloo.subwaysurf",
                                                   runnable: true)]),
      .play(SoloPrimaryGame(id: "B", label: "Subway Surfers 2", packageName: "com.kiloo.subwaysurf")))

// Its folder can be removed in Files, or a copy can be half-finished: the games then say so, by name.
equal("a chosen game whose files are gone names itself",
      SoloLaunch.plan(primary: SoloPrimaryGame(id: "C", label: "Minecraft"), installed: [geometryDash]),
      .choose(.chosenGameRemoved(label: "Minecraft")))

equal("a chosen game with no ARM code does not start",
      SoloLaunch.plan(primary: SoloPrimaryGame(id: "D", label: "x86 Only"),
                      installed: [SoloLibraryEntry(id: "D", label: "x86 Only", packageName: nil, runnable: false)]),
      .choose(.chosenGameCannotRun(label: "x86 Only")))

equal("every reason names the way out", SoloLaunchIssue.nothingChosen.message.contains("Pick the game"), true)
check("a removed game's message names it", SoloLaunchIssue.chosenGameRemoved(label: "Minecraft").message.contains("Minecraft"))
check("an unreadable game's message names it", SoloLaunchIssue.chosenGameCannotRun(label: "x86 Only").message.contains("x86 Only"))

// MARK: - remembering

section("remembering the chosen game")

let suite = "droidnest.solo.checks"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
let store = SoloSelectionStore(defaults: defaults)

equal("nothing is remembered at first", store.load(), nil)

store.save(SoloPrimaryGame(id: "A", label: "Geometry Dash", packageName: "com.robtopx.geometryjump"))
equal("a chosen game reads back", store.load(),
      SoloPrimaryGame(id: "A", label: "Geometry Dash", packageName: "com.robtopx.geometryjump"))

// A different UserDefaults object on the same suite is what the next launch of the app does.
let nextLaunch = SoloSelectionStore(defaults: UserDefaults(suiteName: suite)!)
equal("it survives the app being closed", nextLaunch.load()?.id, "A")

store.save(SoloPrimaryGame(id: "B", label: "Subway Surfers"))
equal("choosing another game replaces it", store.load()?.id, "B")
equal("a game with no package name still reads back", store.load()?.packageName, nil)

store.save(nil)
equal("forgetting it leaves nothing", store.load(), nil)

defaults.removePersistentDomain(forName: suite)

// MARK: - importing

section("what an import takes")

for name in ["game.apk", "GAME.APK", "bundle.xapk", "bundle.apkm", "bundle.apks", "main.1.com.game.obb"] {
    check("takes \(name)", SoloImport.accepts(name))
}
for name in ["notes.txt", "game.zip", "icon.png", "game.apk.part", "README"] {
    check("refuses \(name)", !SoloImport.accepts(name))
}

equal("no file at all is its own answer",
      SoloImport.rejection(for: [], free: 8_000_000_000), .nothingChosen)
equal("a file that is not an APK is refused by name",
      SoloImport.rejection(for: [(name: "notes.txt", bytes: 10)], free: 8_000_000_000),
      .unsupportedFile("notes.txt"))
equal("a file that fits is let through",
      SoloImport.rejection(for: [(name: "game.apk", bytes: 200_000_000)], free: 8_000_000_000), nil)
equal("a file that fills the phone is refused before the copy starts",
      SoloImport.rejection(for: [(name: "game.apk", bytes: 900_000_000)], free: 950_000_000, headroom: 100_000_000),
      .notEnoughSpace(needed: 900_000_000, free: 950_000_000))
equal("several files add up",
      SoloImport.rejection(for: [(name: "a.apk", bytes: 400_000_000), (name: "b.apk", bytes: 400_000_000)],
                           free: 900_000_000, headroom: 100_000_000),
      .notEnoughSpace(needed: 800_000_000, free: 900_000_000))
equal("free space that could not be read is not a refusal",
      SoloImport.rejection(for: [(name: "game.apk", bytes: 4_000_000_000)], free: 0), nil)
check("the space message says how much is needed",
      SoloImportRejection.notEnoughSpace(needed: 1_000_000_000, free: 500_000_000).message.contains("not enough room"))

// MARK: - three fingers

section("three fingers held for five seconds")

var hold = ThreeFingerHold()
equal("nothing is happening", hold.phase, .idle)
equal("two fingers are not the gesture", hold.fingersChanged(to: 2, at: 100), .idle)
equal("a fourth finger on its own is not either", hold.fingersChanged(to: 4, at: 100), .idle)

equal("three fingers start it", hold.fingersChanged(to: 3, at: 100), .holding(progress: 0))
equal("a second in", hold.tick(at: 101), .holding(progress: 0.2))
equal("halfway", hold.tick(at: 102.5), .holding(progress: 0.5))
equal("two seconds to go", hold.tick(at: 103), .holding(progress: 0.6))
equal("five seconds is the way out", hold.tick(at: 105), .reached)
equal("staying down does not fire it twice", hold.tick(at: 108), .reached)

var broken = ThreeFingerHold()
_ = broken.fingersChanged(to: 3, at: 0)
_ = broken.tick(at: 4.9)
equal("a finger lifted at 4.9 s is not the gesture", broken.fingersChanged(to: 2, at: 4.9), .cancelled)
equal("and it stays cancelled until three are put back", broken.tick(at: 6), .idle)

var late = ThreeFingerHold()
_ = late.fingersChanged(to: 3, at: 0)
_ = late.tick(at: 2)
equal("a fourth finger joining breaks it", late.fingersChanged(to: 4, at: 2), .cancelled)

var twice = ThreeFingerHold()
_ = twice.fingersChanged(to: 3, at: 0)
equal("the first hold works", twice.tick(at: 5), .reached)
_ = twice.fingersChanged(to: 2, at: 5.2)
_ = twice.fingersChanged(to: 0, at: 5.4)
equal("and a second one, later in the session, works too",
      twice.fingersChanged(to: 3, at: 20) == .holding(progress: 0) ? twice.tick(at: 25) : .idle, .reached)

var allThreeAtOnce = ThreeFingerHold()
equal("a game's own three-finger chord, tapped, never reaches the exit",
      allThreeAtOnce.fingersChanged(to: 3, at: 0) == .idle ? .idle : allThreeAtOnce.fingersChanged(to: 0, at: 0.2),
      .cancelled)

// Progress has to be a ring that fills, not a value that runs past either end.
var ring = ThreeFingerHold()
_ = ring.fingersChanged(to: 3, at: 0)
var last = 0.0
for step in stride(from: 0.0, through: 5.2, by: 0.1) {
    if case .holding(let p) = ring.tick(at: step) {
        check("progress only ever goes forward (\(step)s)", p >= last)
        check("progress stays within the ring (\(step)s)", p >= 0 && p <= 1)
        last = p
    }
}

// MARK: - the one game a session can hold

section("one game per launch")

let conflict = SoloSessionConflict(running: "Subway Surfers", wantedID: "A", wantedLabel: "Geometry Dash")
check("the conflict names what is running", conflict.message.contains("Subway Surfers"))
check("and what is now chosen", conflict.message.contains("Geometry Dash"))
check("and says what to do", conflict.message.lowercased().contains("opened again"))

// MARK: - result

print("")
if failures == 0 {
    print("all \(checks) checks passed")
} else {
    print("\(failures) of \(checks) checks failed")
    exit(1)
}
