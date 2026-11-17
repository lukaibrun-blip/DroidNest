// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// DroidNest's settings: everything the app does, in one place, with the two things that matter when something goes
/// wrong at the top -- the logs of this run and the report of the last crash.
///
/// It is written in the console's own pieces (Console's palette, Theme's accent, HuskPageList's cards) rather than as a
/// second design beside them, and every switch here is one the app actually honours.
struct SoloSettingsView: View {
    @ObservedObject private var solo = SoloStore.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @AppStorage(SoloGesture.exitKey) private var exitGesture = true
    @AppStorage(SoloSettings.autoJITKey) private var autoJIT = true
    @AppStorage(SoloSettings.keepRunningKey) private var keepRunning = true
    @AppStorage(JITLess.key) private var jitLess = false
    @State private var confirmingRemoveAll = false
    @State private var showingSetup = false
    @State private var crashing: CrashReport.Report?

    var body: some View {
        HuskPageList {
            diagnostics
            jitSection
            playSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { solo.refresh() }
        .sheet(isPresented: $showingSetup) { JITSetupFlow() }
        .sheet(item: $crashing) { report in CrashReportSheet(report: report) }
        .confirmationDialog("Delete every saved crash report?", isPresented: $confirmingRemoveAll,
                            titleVisibility: .visible) {
            Button("Delete Reports", role: .destructive) { SoloCrashLog.removeAll() }
            Button("Keep Them", role: .cancel) {}
        } message: {
            Text("The logs of the runs themselves are kept: only the reports DroidNest saved from them are removed.")
        }
    }

    // MARK: - diagnostics: the two that matter

    private var diagnostics: some View {
        Section {
            NavigationLink {
                SoloLogsView()
            } label: {
                row("View Logs", detail: "This run, the last one, and what the game printed",
                    symbol: "doc.text.magnifyingglass")
            }

            NavigationLink {
                SoloLogsView()
            } label: {
                row("View Last Crash Log", detail: SoloCrashLog.hasAny
                        ? "What stopped the last game, and the log of that run"
                        : "Nothing has crashed yet: this fills in when a game ends DroidNest",
                    symbol: "exclamationmark.triangle")
            }
            .disabled(false)

            if let report = CrashReport.shared.pending {
                Button {
                    crashing = report
                } label: {
                    row("\(report.game) did not close normally", detail: report.cause.title,
                        symbol: "waveform.path.ecg")
                }
            }

            Button(role: .destructive) {
                confirmingRemoveAll = true
            } label: {
                row("Delete Saved Crashes", detail: "\(SoloCrashLog.all().count) saved",
                    symbol: "trash", destructive: true)
            }
            .disabled(!SoloCrashLog.hasAny)
        } header: {
            Text("If Something Went Wrong")
        } footer: {
            Text("DroidNest saves the report of every crash by itself, at the moment it notices one. Nothing is sent "
                 + "anywhere unless you share it.")
        }
    }

    // MARK: - JIT

    private var jitSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: JITBootstrap.ready ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(JITBootstrap.ready ? .green : Color.orange)
                    .frame(width: 30, height: 30)
                    .background((JITBootstrap.ready ? Color.green : Color.orange).opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(JITBootstrap.ready ? "JIT is on" : "JIT is off")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Console.text)
                    Text(SoloJIT.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Console.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !JITBootstrap.ready {
                Button { SoloJIT.turnOn() } label: {
                    row(jit.method == .builtIn || HuskBuiltInJIT.isAvailable ? "Turn On JIT (StikJIT)" : "Turn On JIT",
                        detail: "No computer and no other app, where this iOS allows it", symbol: "bolt.badge.clock")
                }
                Button { showingSetup = true } label: {
                    row("Set Up JIT", detail: "The walkthrough, and the other four ways", symbol: "questionmark.circle")
                }
            }

            Toggle(isOn: $autoJIT) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn JIT on when DroidNest opens")
                        .font(.system(size: 15))
                        .foregroundStyle(Console.text)
                    Text("The built-in helper attaches as the app comes up, so a game starts without a step in front of it.")
                        .font(.system(size: 11))
                        .foregroundStyle(Console.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)

            Toggle(isOn: $jitLess) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JIT-less mode")
                        .font(.system(size: 15))
                        .foregroundStyle(Console.text)
                    Text("A game's libraries are converted to signed dylibs once and then need no executable memory at all. "
                         + "Works with the certificate that installed DroidNest; an engine that writes its own code still "
                         + "needs JIT.")
                        .font(.system(size: 11))
                        .foregroundStyle(Console.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("JIT")
        } footer: {
            Text("A game's own ARM code has to run from memory it can write and then execute, and iOS only gives an app "
                 + "that memory through a debugger. DroidNest reuses Husk's five ways of getting one, and claims nothing "
                 + "beyond what this device allows.")
        }
    }

    // MARK: - playing

    private var playSection: some View {
        Section {
            Toggle(isOn: $exitGesture) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Three fingers held for five seconds leaves the game")
                        .font(.system(size: 15))
                        .foregroundStyle(Console.text)
                    Text("A fourth finger, or one lifting early, cancels it, and DroidNest asks before it leaves. Turn this "
                         + "off for a game that wants three fingers of its own.")
                        .font(.system(size: 11))
                        .foregroundStyle(Console.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)

            Toggle(isOn: $keepRunning) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep the game running when you go back")
                        .font(.system(size: 15))
                        .foregroundStyle(Console.text)
                    Text("Off, turning the screen off or leaving the app ends the game. On, it keeps drawing in the "
                         + "background, which costs battery.")
                        .font(.system(size: 11))
                        .foregroundStyle(Console.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
        } header: {
            Text("Playing")
        }
    }

    // MARK: - about

    private var aboutSection: some View {
        Section {
            Button {
                HuskFilePicker.present(types: [.item, .data], multiple: true) { urls in
                    solo.importFiles(urls)
                } onFail: { solo.error = $0 }
            } label: {
                row("Add an APK", detail: "From Files, iCloud Drive or a USB stick", symbol: "plus.circle")
            }

            NavigationLink { SoloStorageView() } label: {
                row("Storage", detail: "What the games take, and what is free", symbol: "internaldrive")
            }

            HStack(spacing: 12) {
                Image(systemName: "app.badge")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("DroidNest \(SoloAbout.version)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Console.text)
                    Text("Core: \(DNCore.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(Console.textDim)
                }
                Spacer(minLength: 0)
            }
        } header: {
            Text("About")
        } footer: {
            Text(SoloAbout.nameNote + " Built on Husk, GPL-2.0-or-later.")
        }
    }

    // MARK: - one row

    private func row(_ title: String, detail: String, symbol: String, destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(destructive ? Color.red : Theme.accent)
                .frame(width: 30, height: 30)
                .background((destructive ? Color.red : Theme.accent).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(destructive ? Color.red : Console.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Console.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// How much room the games take, and what is left: the question a person actually asks before adding a fourth APK.
struct SoloStorageView: View {
    @ObservedObject private var solo = SoloStore.shared

    private var total: Int64 {
        solo.apps.reduce(Int64(0)) { sum, app in
            sum + app.apks.reduce(Int64(0)) { inner, path in
                inner + (((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0)
            }
        }
    }

    private var crashes: Int64 {
        SoloCrashLog.all().reduce(Int64(0)) { sum, url in
            sum + (((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0)
        }
    }

    var body: some View {
        HuskPageList {
            Section {
                labelled("Games", SoloImport.size(total))
                labelled("Crash reports", SoloImport.size(crashes))
                labelled("Free on this iPhone", SoloImport.size(SoloStore.freeBytes()))
            } header: {
                Text("Storage")
            } footer: {
                Text("Every APK DroidNest holds, and everything it saved beside them. Removing a game is the only thing "
                     + "that deletes an APK, and it always asks first.")
            }

            Section {
                ForEach(solo.apps) { app in
                    labelled(app.label, SoloImport.size(app.apks.reduce(Int64(0)) { sum, path in
                        sum + (((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0)
                    }))
                }
            } header: {
                Text("Each game")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { solo.refresh() }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Console.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Console.textDim)
        }
    }
}
