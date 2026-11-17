// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// Every log DroidNest keeps, on one page, with the report of the run that ended at the top.
///
/// A game runs inside DroidNest's process, so a crash leaves nothing behind but text on disk: `husk.log` (this run),
/// `husk-prev.log` (the run before it), `husk-native.log` and `husk-native-prev.log` (what the game's own C code printed),
/// and `DroidNest/crashes/last-crash.txt` (what DroidNest made of the last one). Reading them on the phone, with no Mac and
/// no Console.app, is the whole point of this page.
struct SoloLogsView: View {
    @State private var source: Source = .previous
    @State private var text = ""
    @State private var loading = true
    @State private var sharing: SharedFile?
    @State private var query = ""

    enum Source: String, CaseIterable, Identifiable {
        case previous, current, native, crash

        var id: String { rawValue }

        var title: String {
            switch self {
            case .previous: return "Last run"
            case .current: return "This run"
            case .native: return "Game output"
            case .crash: return "Last crash"
            }
        }

        var file: URL {
            switch self {
            case .previous: return CrashReport.previousLogURL
            case .current: return HuskLog.logFileURL
            case .native: return HuskLog.nativeLogURL
            case .crash: return SoloCrashLog.latest
            }
        }

        /// Whether there is a file to read. "This run" is always written to as the app runs, so it is always offered.
        var exists: Bool { self == .current || FileManager.default.fileExists(atPath: file.path) }
    }

    /// The chosen log, narrowed to what was searched for.
    private var shown: String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return text }
        // Matching lines only: a log is thousands of lines long, and the ones without the word are noise.
        let hits = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(needle) }
        return hits.isEmpty ? "Nothing in this log matches “\(needle)”." : hits.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            picker
            Divider().overlay(Console.hairline)
            if loading {
                Spacer()
                ProgressView("Reading…")
                Spacer()
            } else if text.isEmpty {
                Spacer()
                empty
                Spacer()
            } else {
                log
            }
        }
        .background(Console.page.ignoresSafeArea())
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if FileManager.default.fileExists(atPath: source.file.path) {
                        Button { sharing = SharedFile(url: source.file) } label: {
                            Label("Share This Log", systemImage: "square.and.arrow.up")
                        }
                    }
                    if SoloCrashLog.hasAny {
                        Button { sharing = SharedFile(url: SoloCrashLog.latest) } label: {
                            Label("Share Last Crash Report", systemImage: "exclamationmark.triangle")
                        }
                    }
                    Divider()
                    Button(role: .destructive) { SoloCrashLog.removeAll() } label: {
                        Label("Delete Saved Crashes", systemImage: "trash")
                    }
                    .disabled(!SoloCrashLog.hasAny)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: source) { load() }
        .sheet(item: $sharing) { file in ShareSheet(items: [file.url]) }
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Source.allCases) { candidate in
                    Button {
                        source = candidate
                    } label: {
                        Text(candidate.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(candidate == source ? .white : Console.text)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(candidate == source ? Theme.accent : Console.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!candidate.exists)
                    .opacity(candidate.exists ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var log: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Console.textDim)
                TextField("Find in this log", text: $query)
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Console.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Console.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView {
                Text(shown)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Console.text.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Console.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Console.textDim)
            Text(source == .crash ? "No crash has been saved yet" : "This log is empty")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Console.text)
            Text(source == .crash
                 ? "When a game ends DroidNest, the next launch writes the report here: what stopped it, the build and "
                   + "device it was on, and the last lines of that run."
                 : "DroidNest writes this file as it runs. Open it again once something has happened.")
                .font(.system(size: 12))
                .foregroundStyle(Console.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
    }

    private func load() {
        loading = true
        let url = source.file
        // Off the main thread: the native log of a game that ran for an hour is megabytes, and reading it on the main
        // thread would freeze the very page that exists to show it.
        Task.detached(priority: .userInitiated) {
            let whole = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let capped: String
            if whole.utf8.count > 400_000 {
                capped = "(the last 400 KB of this log; the newest lines are at the bottom)\n\n"
                       + SoloLogsView.tail(whole, bytes: 400_000)
            } else {
                capped = whole
            }
            await MainActor.run {
                text = capped
                loading = false
            }
        }
    }

    /// The last `bytes` of a string, starting on a line boundary so the first line is whole.
    nonisolated static func tail(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var seen = 0
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            seen += String(text[previous]).utf8.count
            if seen >= bytes { break }
            index = previous
        }
        // Forward to the next newline: half a timestamp at the top helps nobody.
        if let newline = text[index...].firstIndex(of: "\n") {
            return String(text[text.index(after: newline)...])
        }
        return String(text[index...])
    }
}

/// A file the share sheet can be opened on. `URL` is not `Identifiable`, and `.sheet(item:)` needs something that is.
private struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}
