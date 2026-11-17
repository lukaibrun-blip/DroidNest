// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

/// The games: the one that opens, and every APK DroidNest holds.
///
/// It is built from Husk's own pieces -- its library store (icons, names, sizes, reports), its file picker, its JIT card and
/// its setup walkthrough -- rather than being a second, thinner launcher beside them.
struct SoloManagerView: View {
    /// A game was chosen: it is now the main one, and it should open.
    let onPlay: (TLApp) -> Void

    @ObservedObject private var solo = SoloStore.shared
    @ObservedObject private var jit = JITCoordinator.shared
    @State private var confirmingRemove: TLApp?

    var body: some View {
        NavigationStack {
            page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let issue = solo.launchIssue { notice(issue.message, tint: Theme.accent) }
                if let importing = solo.importing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Adding \(importing)…").font(.subheadline).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Console.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                mainGame
                jitSection
                games
                shortcuts
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Console.page.ignoresSafeArea())
        .onAppear { solo.refresh() }
        .sheet(isPresented: $jit.showSetup) { JITSetupFlow() }
        .alert("Something is not right", isPresented: Binding(
            get: { solo.error != nil },
            set: { if !$0 { solo.error = nil } })) {
            Button("OK", role: .cancel) { solo.error = nil }
        } message: {
            Text(solo.error ?? "")
        }
        .alert("Close DroidNest?", isPresented: Binding(
            get: { solo.conflict != nil },
            set: { if !$0 { solo.conflict = nil } })) {
            Button("Keep Playing", role: .cancel) { solo.conflict = nil }
            Button("Close DroidNest") { solo.restartIntoWantedGame() }
        } message: {
            Text(solo.conflict?.message ?? "")
        }
        .confirmationDialog("Remove \(confirmingRemove?.label ?? "this game")?",
                            isPresented: Binding(get: { confirmingRemove != nil },
                                                 set: { if !$0 { confirmingRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let app = confirmingRemove { solo.remove(app) }
                confirmingRemove = nil
            }
            Button("Cancel", role: .cancel) { confirmingRemove = nil }
        } message: {
            Text("Its APK and everything it saved are deleted from DroidNest. Nothing else is touched.")
        }
    }

    // MARK: the top

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DroidNest")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Console.text)
                Text("One game at a time")
                    .font(.system(size: 13))
                    .foregroundStyle(Console.textDim)
            }
            Spacer(minLength: 0)
            Button(action: importAPK) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add an APK")
        }
        .padding(.top, 4)
    }

    private func notice(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Console.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    // MARK: the chosen game

    @ViewBuilder
    private var mainGame: some View {
        if let app = solo.primaryApp {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    AppIcon(path: app.iconPath, size: 76)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.label)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Console.text)
                            .lineLimit(2)
                        Text("Opens by itself when DroidNest starts")
                            .font(.system(size: 12))
                            .foregroundStyle(Console.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        if let runner = app.report?.runnerName {
                            Text(runner)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Console.textDim)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Button { onPlay(app) } label: {
                    HStack {
                        Spacer()
                        Label(SoloJIT.readyOrJITLess ? "Play Now" : "Turn On JIT, Then Play", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .frame(height: 50)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Console.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Console.outline, lineWidth: 0.5))
        } else if solo.apps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No games yet")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Console.text)
                Text("Tap + and choose an APK from Files. DroidNest keeps it in its own storage, reads its name and icon, and "
                     + "opens it full screen from then on -- and the next APK you add joins it in this list, so you can switch "
                     + "between games whenever you like.")
                    .font(.system(size: 13))
                    .foregroundStyle(Console.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Console.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: JIT

    @ViewBuilder
    private var jitSection: some View {
        if !JITBootstrap.ready {
            VStack(alignment: .leading, spacing: 10) {
                Text("JIT")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Console.text)
                // Husk's own card: the same explanation, the same five ways, the same walkthrough.
                JITCard()
                Text("DroidNest turns JIT on by itself as it opens when StikJIT is paired, or when it was installed through "
                     + "TrollStore. Only where neither is possible does turning it on need a tap.")
                    .font(.system(size: 12))
                    .foregroundStyle(Console.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: every game

    @ViewBuilder
    private var games: some View {
        if !solo.apps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Your games")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Console.text)
                    Text("\(solo.apps.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Console.textDim)
                    Spacer(minLength: 0)
                    Button("Add") { importAPK() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(spacing: 2) {
                    ForEach(solo.apps) { app in
                        row(app)
                        if app.id != solo.apps.last?.id {
                            Rectangle()
                                .fill(Console.hairline)
                                .frame(height: 1)
                                .padding(.leading, 68)
                        }
                    }
                }
                .background(Console.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func row(_ app: TLApp) -> some View {
        let isMain = solo.primary?.id == app.id
        return Button { onPlay(app) } label: {
            HStack(spacing: 14) {
                AppIcon(path: app.iconPath, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Console.text)
                        .lineLimit(1)
                    Text(subtitle(app))
                        .font(.system(size: 11))
                        .foregroundStyle(Console.textDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isMain {
                    Text("MAIN")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                } else {
                    Image(systemName: "play.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Console.textDim)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onPlay(app) } label: { Label("Play Now", systemImage: "play.fill") }
            if !isMain {
                Button { solo.setPrimary(app) } label: {
                    Label("Open This at Launch", systemImage: "house.fill")
                }
            }
            Divider()
            Button(role: .destructive) { confirmingRemove = app } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// What the row says under the name: how it runs, how big it is, and when it was last played.
    private func subtitle(_ app: TLApp) -> String {
        var parts: [String] = []
        if let runner = app.report?.runnerName { parts.append(runner) }
        else if app.report == nil { parts.append("Couldn't read this APK") }
        parts.append(bytes(app))
        if let played = app.lastPlayed {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            parts.append("played " + f.localizedString(for: played, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private func bytes(_ app: TLApp) -> String {
        let total = app.apks.reduce(Int64(0)) { sum, path in
            sum + (((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    // MARK: settings

    /// The way into Settings, which has everything else: JIT, the switches, the logs and the last crash report.
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DroidNest")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Console.text)

            VStack(spacing: 0) {
                NavigationLink { SoloSettingsView() } label: {
                    shortcut("Settings", detail: SoloJIT.summary, symbol: "gearshape")
                }
                .buttonStyle(.plain)
                Rectangle().fill(Console.hairline).frame(height: 1).padding(.leading, 58)
                NavigationLink { SoloLogsView() } label: {
                    shortcut("Logs", detail: SoloCrashLog.hasAny
                                ? "The last crash, and every log of that run"
                                : "This run, the last one, and what the game printed",
                             symbol: "doc.text.magnifyingglass")
                }
                .buttonStyle(.plain)
            }
            .background(Console.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func shortcut(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Console.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Console.textDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Console.textDim)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Built on Husk · GPL-2.0-or-later")
                .font(.system(size: 11))
                .foregroundStyle(Console.textDim)
            Text("Games are Android apps you supply. Nothing here is downloaded for you.")
                .font(.system(size: 11))
                .foregroundStyle(Console.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    // MARK: importing

    /// The system's file picker, presented from UIKit -- Husk's own, which is the one that survives a sideloaded install
    /// (SwiftUI's `.fileImporter` goes quiet on certificate-signed builds).
    private func importAPK() {
        HuskFilePicker.present(types: [.item, .data], multiple: true) { urls in
            solo.importFiles(urls)
        } onFail: { message in
            solo.error = message
        }
    }
}
