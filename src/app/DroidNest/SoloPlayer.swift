// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

/// A game, full screen, with a way back that is not a button left over someone's game.
///
/// The game itself is Husk's own screen (`TLAttemptView`, which picks the right runtime for the engine it is): this puts it on
/// screen and watches for three fingers held down for five seconds. Holding shows a ring filling for the last seconds, and then
/// asks before it leaves, so a game that wants three fingers at once cannot throw someone out by being played.
struct SoloPlayer: View {
    let app: TLApp
    let onExit: () -> Void

    /// Off for a game that needs three fingers of its own (Settings in the games list).
    @AppStorage(SoloGesture.exitKey) private var exitGesture = true
    @State private var phase: ThreeFingerHold.Phase = .idle
    @State private var asking = false

    var body: some View {
        ZStack {
            TLAttemptView(app: app)

            // A passive watcher: it takes no touch away from the game and never cancels one.
            if exitGesture {
                ThreeFingerHoldOverlay { phase = $0 }
                    .allowsHitTesting(false)
            }
            if case .holding(let progress) = phase, progress > 0.04, !asking {
                countdown(progress)
            }
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .reached, !asking { asking = true }
        }
        .alert("Leave \(app.label)?", isPresented: $asking) {
            Button("Keep Playing", role: .cancel) { phase = .idle }
            // The bar DroidNest opens on: the game stops, and another APK can be chosen or added.
            Button("Leave Game") {
                phase = .idle
                HuskLog.log("droidnest", "three fingers held: leaving \(app.label)")
                onExit()
            }
        } message: {
            Text("The game stops and your games open, where you can choose another one or add a new APK.")
        }
    }

    /// The ring that fills while three fingers are held: the sign that something is happening before anything happens.
    private func countdown(_ progress: Double) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                Text("Keep holding to open your games")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.62), in: Capsule())
            .padding(.bottom, 44)
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.15), value: progress)
    }
}

// MARK: - the gesture

/// Watches the window for three fingers held down, and reports what `ThreeFingerHold` makes of it.
///
/// It is attached to the window rather than to a view of its own, so the game keeps every touch: a recognizer that never
/// recognizes can see touches without taking them, and this one never enters `.began`, `.ended` or `.failed`.
struct ThreeFingerHoldOverlay: UIViewRepresentable {
    let onChange: (ThreeFingerHold.Phase) -> Void

    final class Coordinator {
        var onChange: (ThreeFingerHold.Phase) -> Void
        init(onChange: @escaping (ThreeFingerHold.Phase) -> Void) { self.onChange = onChange }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> HoldHostView {
        let view = HoldHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false   // taken touches here would be touches taken from the game
        view.recognizer.onChange = { context.coordinator.onChange($0) }
        return view
    }

    func updateUIView(_ view: HoldHostView, context: Context) {
        context.coordinator.onChange = onChange
        view.recognizer.onChange = { context.coordinator.onChange($0) }
    }

    static func dismantleUIView(_ view: HoldHostView, coordinator: Coordinator) {
        view.detach()
    }
}

/// The view that keeps the recognizer on the window it finds itself in, and takes it off again.
final class HoldHostView: UIView {
    let recognizer = ThreeFingerHoldRecognizer(target: nil, action: nil)
    private weak var attachedTo: UIWindow?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            if attachedTo !== window {
                detach()
                window.addGestureRecognizer(recognizer)
                attachedTo = window
                HuskLog.log("droidnest", "three-finger exit watching this window")
            }
        } else {
            detach()
        }
    }

    /// Called when the game screen goes: a recognizer left on the window would keep reporting into a screen that is gone.
    func detach() {
        recognizer.invalidate()
        if let window = attachedTo {
            window.removeGestureRecognizer(recognizer)
            attachedTo = nil
        }
    }
}

/// Three fingers held for five seconds, reported as progress, and taking nothing from the game.
///
/// A passive gesture recognizer: it stays in `.possible` for its whole life, so it cancels no touch and blocks no other
/// recognizer. What counts as the gesture is `ThreeFingerHold`'s decision (SoloCore.swift), which is checked on a Mac.
final class ThreeFingerHoldRecognizer: UIGestureRecognizer {
    var onChange: ((ThreeFingerHold.Phase) -> Void)?

    private var hold = ThreeFingerHold()
    private var timer: Timer?
    private var reported: ThreeFingerHold.Phase = .idle

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        update(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        update(event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        update(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        update(event)
    }

    private func update(_ event: UIEvent) {
        // Fingers still on the glass: an ended or cancelled one is on its way out and must not count.
        let down = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        report(hold.fingersChanged(to: down, at: CACurrentMediaTime()))
        if hold.isHolding || hold.phase == .reached { startTimer() } else { stopTimer() }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let phase = hold.tick(at: CACurrentMediaTime())
        report(phase)
        if phase == .reached || phase == .idle || phase == .cancelled { stopTimer() }
    }

    /// Only changes are reported: the ring is drawn from progress, and a callback per frame for the same value would redraw
    /// a game's screen for nothing.
    private func report(_ phase: ThreeFingerHold.Phase) {
        guard phase != reported else { return }
        reported = phase
        onChange?(phase)
    }

    /// Let go of everything: used when the game screen goes away.
    func invalidate() {
        stopTimer()
        hold.reset()
        onChange = nil
    }

    override func reset() {
        super.reset()
        stopTimer()
        hold.reset()
        reported = .idle
    }
}
