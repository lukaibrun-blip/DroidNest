// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import UIKit

/// What an APK says about itself before it is copied: its first bytes, and the Android package in its manifest.
///
/// Both are read straight out of the zip without unpacking it: the manifest is stored uncompressed in practice, and when it
/// is not, no answer is the honest one -- the copy itself will find out.
enum SoloAPKProbe {
    struct Reading {
        /// Enough of the file's beginning to recognise a zip (or not one).
        var head: Data = Data()
        /// Its Android package name, when the manifest could be read here.
        var package: String?
    }

    /// Read for the import check. Never throws: anything unreadable comes back empty, which the core treats as "no evidence"
    /// rather than as a refusal.
    static func head(of url: URL) -> Reading {
        var reading = Reading()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return reading }
        defer { try? handle.close() }

        // The zip signature and nothing more: 64 bytes is what the core looks at.
        reading.head = (try? handle.read(upToCount: 64)) ?? Data()

        // The package name, so a game that is already here is not silently duplicated.
        if let manifest = manifestEntry(of: url) {
            reading.package = ApkMetadata.packageName(manifest)
        }
        return reading
    }

    /// `AndroidManifest.xml`, read through Husk's own zip reader (husk_tl_read_entry), which is what the importer uses.
    private static func manifestEntry(of url: URL) -> Data? {
        TranslationLayerStore.entry(url.path, "AndroidManifest.xml", limit: 8 << 20)
    }
}

/// How long DroidNest is allowed to go on after the person leaves the app while a game is open.
///
/// iOS suspends an app that goes to the background, and a game that stops mid-frame usually comes back to a black screen.
/// `beginBackgroundTask` is iOS's own answer: it keeps the app running for a short while after it leaves the screen, which
/// covers a glance at a notification or a switch between apps. It is not a promise that a game keeps drawing forever, and
/// the settings say so.
@MainActor
enum SoloBackground {
    private static var task: UIBackgroundTaskIdentifier?

    static func begin(_ name: String) {
        guard task == nil else { return }
        // The expiry handler takes no argument on this SDK: it is @MainActor and @Sendable, so it hops back rather than
        // touching the identifier from whichever thread iOS calls it on. `expire()` ends whatever is held at that moment,
        // which is this task or nothing.
        task = UIApplication.shared.beginBackgroundTask(withName: name) {
            Task { @MainActor in SoloBackground.expire() }
        }
        HuskLog.log("droidnest", "asked iOS for time after leaving the screen (\(name))")
    }

    static func end() {
        guard let live = task else { return }
        if live != .invalid { UIApplication.shared.endBackgroundTask(live) }
        task = nil
    }

    /// iOS ran out of time for the task being held: give it up, so the next `begin` is not refused.
    private static func expire() {
        guard let live = task else { return }
        if live != .invalid { UIApplication.shared.endBackgroundTask(live) }
        task = nil
    }
}
