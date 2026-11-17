// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// DroidNest's own core, which is Rust (src/droidnest-core), behind the C interface in DroidNestCore.h.
///
/// Two things live over there and nothing else: what an import is (decided before a byte is copied, which Husk's importer
/// does not do), and why the last run stopped (read from the log the run wrote as it died). Both are pure functions over
/// bytes, checked by `cargo test` on any machine -- tests/core/run.sh -- so the parts of DroidNest that can be proven are
/// proven without a phone.
enum DNCore {
    // MARK: - what an import is

    enum Verdict: Equatable {
        /// Go ahead, and there is nothing to say about it.
        case accept
        /// Go ahead, but say this first.
        case note(String)
        /// Do not copy it, and say this.
        case refuse(String)

        var refusal: String? {
            if case .refuse(let why) = self { return why }
            return nil
        }

        var note: String? {
            if case .note(let why) = self { return why }
            return nil
        }
    }

    /// Whether a file should be copied in, decided from its name, its first bytes, its size and the room there is.
    static func check(name: String, head: Data, bytes: Int64, free: Int64, installed: Bool = false) -> Verdict {
        // The core reads at most a zip signature's worth of header, and says so in its own documentation.
        let headBytes = [UInt8](head.prefix(64))
        let nameBytes = Array(name.utf8)
        var out = [UInt8](repeating: 0, count: 1024)

        let code: Int32 = out.withUnsafeMutableBufferPointer { outBuffer in
            nameBytes.withUnsafeBufferPointer { nameBuffer in
                headBytes.withUnsafeBufferPointer { headBuffer in
                    droidnest_import_check(nameBuffer.baseAddress, nameBuffer.count,
                                           headBuffer.baseAddress, headBuffer.count,
                                           UInt64(max(bytes, 0)), UInt64(max(free, 0)),
                                           installed ? 1 : 0,
                                           outBuffer.baseAddress, outBuffer.count)
                }
            }
        }

        let sentence = String(decoding: out.prefix { $0 != 0 }, as: UTF8.self)
        switch code {
        case 0: return .accept
        case 1: return .note(sentence)
        default: return .refuse(sentence)
        }
    }

    // MARK: - why the last run stopped

    struct Crash: Equatable {
        enum Kind: Equatable {
            case unknown
            case signal(Int32)
            case startFailed
            case outOfMemory
        }

        var kind: Kind
        /// One line: what happened.
        var title: String
        /// A paragraph: what it means, and what can be done.
        var detail: String
    }

    /// What the last run's log says. `log` is that run's text; the core looks for the last `*** FATAL SIGNAL n` in it,
    /// then for a runtime refusal, then for iOS reclaiming the memory.
    static func classify(log: String) -> Crash {
        // The tail is where a crash is: the beginning of a long log is start-up chatter.
        let bytes = [UInt8](log.suffix(512 * 1024).utf8)
        var out = [UInt8](repeating: 0, count: 1024)
        var code: Int32 = 0
        var signal: Int32 = 0

        bytes.withUnsafeBufferPointer { logBuffer in
            code = droidnest_crash_code(logBuffer.baseAddress, logBuffer.count)
            signal = droidnest_crash_signal(logBuffer.baseAddress, logBuffer.count)
            out.withUnsafeMutableBufferPointer { outBuffer in
                _ = droidnest_crash_describe(logBuffer.baseAddress, logBuffer.count,
                                             outBuffer.baseAddress, outBuffer.count)
            }
        }

        // "Title\n\nDetail", which is what the core writes.
        let text = String(decoding: out.prefix { $0 != 0 }, as: UTF8.self)
        let split = text.components(separatedBy: "\n\n")
        let title = split.first ?? "DroidNest closed while the game was running"
        let detail = split.dropFirst().joined(separator: "\n\n")

        let kind: Crash.Kind
        switch code {
        case 1: kind = .signal(signal)
        case 2: kind = .startFailed
        case 3: kind = .outOfMemory
        default: kind = .unknown
        }
        return Crash(kind: kind,
                     title: title.isEmpty ? "DroidNest closed while the game was running" : title,
                     detail: detail.isEmpty ? "The log of that run is the detail." : detail)
    }

    /// Which core this build carries ("droidnest-core 1"). The settings page shows it, so a report can say whether the
    /// app is actually running the Rust core and not an older build.
    static var version: String {
        guard let text = droidnest_core_version() else { return "not linked" }
        return String(cString: text)
    }
}
