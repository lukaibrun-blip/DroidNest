// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import UIKit

/// Every crash DroidNest has seen, kept so it can be read afterwards.
///
/// A game runs inside DroidNest's own process, so when it dies the app dies with it and nothing can be shown at that
/// moment. Husk writes `running-game.json` while a game is up and one log per run (`husk.log`, and the run before it as
/// `husk-prev.log`); what it does not do is keep the crash. DroidNest does: the next launch notices the marker, writes the
/// run that ended into `Documents/DroidNest/crashes/`, and the settings page can open it at any time afterwards -- not only
/// on the launch right after the crash.
@MainActor
enum SoloCrashLog {
    /// Where the archive lives: DroidNest's own folder, beside the games rather than in them, so removing a game never
    /// removes the record of why it stopped. `nonisolated`: a path is not state, and a view names it to read the file.
    nonisolated static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DroidNest", isDirectory: true)
            .appendingPathComponent("crashes", isDirectory: true)
    }

    /// The one the settings page opens: always the most recent.
    nonisolated static var latest: URL { root.appendingPathComponent("last-crash.txt") }

    /// How many are kept: enough to compare two reports, few enough that they cannot fill the phone.
    private static let keep = 10

    /// At launch, before anything is drawn: if the last run ended with a game up, save why.
    ///
    /// Called after `CrashReport.shared.checkPreviousRun()`, which is what reads and clears Husk's marker. The report it
    /// leaves in `pending` is the evidence, and this turns it into a file that outlives the launch.
    static func archiveIfNeeded(_ report: CrashReport.Report?) {
        guard let report else { return }
        let text = compose(report)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: latest, options: .atomic)
            let stamp = ISO8601DateFormatter().string(from: report.when ?? Date())
                .replacingOccurrences(of: ":", with: "-")
            try Data(text.utf8).write(to: root.appendingPathComponent("crash-\(stamp).txt"), options: .atomic)
            prune()
            HuskLog.log("crash", "saved the report for \(report.game) to \(latest.path)")
        } catch {
            HuskLog.log("crash", "could not save the crash report: \(error.localizedDescription)")
        }
    }

    /// The whole story in one file: what the core read from the log, this device and build, then the run's own output.
    private static func compose(_ report: CrashReport.Report) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let previousLog = (try? String(contentsOf: CrashReport.previousLogURL, encoding: .utf8)) ?? ""
        let native = (try? String(contentsOf: HuskLog.previousNativeLogURL, encoding: .utf8)) ?? ""

        // What DroidNest's Rust core makes of the log, which is the part that can be re-run and checked.
        let read = DNCore.classify(log: previousLog + "\n" + native)

        var lines: [String] = []
        lines.append("DroidNest crash report")
        lines.append("=====================")
        lines.append("Game      : \(report.game)")
        lines.append("When      : \(report.when.map { ISO8601DateFormatter().string(from: $0) } ?? "not recorded")")
        lines.append("What      : \(report.cause.title)")
        lines.append("Read from : \(read.title)")
        lines.append("DroidNest : \(info["CFBundleShortVersionString"] as? String ?? "?") "
                     + "(\(info["CFBundleVersion"] as? String ?? "?")) \(info["HuskBuildCommit"] as? String ?? "unstamped")")
        lines.append("Core      : \(DNCore.version)")
        lines.append("Device    : \(HuskLog.deviceModel), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        lines.append("")
        lines.append(read.detail)
        lines.append("")
        lines.append(report.cause.detail)
        lines.append("")
        lines.append("---- husk.log of that run ----")
        lines.append(previousLog.isEmpty ? "(not kept)" : previousLog)
        lines.append("")
        lines.append("---- native output of that run ----")
        lines.append(native.isEmpty ? "(none)" : native)
        return lines.joined(separator: "\n")
    }

    /// The newest `keep` dated reports, and the always-current `last-crash.txt` on top of them.
    private static func prune() {
        let fm = FileManager.default
        let dated = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]))
            ?? []).filter { $0.lastPathComponent.hasPrefix("crash-") }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        for old in dated.dropFirst(keep) { try? fm.removeItem(at: old) }
    }

    /// The reports there are, newest first. `last-crash.txt` is the first of them.
    static func all() -> [URL] {
        let dated = ((try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("crash-") || $0.lastPathComponent == "last-crash.txt" }
            .sorted { a, b in
                if a.lastPathComponent == "last-crash.txt" { return true }
                if b.lastPathComponent == "last-crash.txt" { return false }
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        return dated
    }

    /// Whether there is anything to show. The settings row is greyed out rather than opening an empty page.
    static var hasAny: Bool { FileManager.default.fileExists(atPath: latest.path) }

    /// Deleting them is an explicit action, and the only one that removes a crash.
    static func removeAll() {
        for url in all() { try? FileManager.default.removeItem(at: url) }
        HuskLog.log("crash", "crash reports removed")
    }
}
