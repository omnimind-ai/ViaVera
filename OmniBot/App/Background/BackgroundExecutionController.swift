import Foundation
import Observation
#if os(iOS)
import AVFoundation
import UIKit
#endif

/// Adapted from OpenMinis' BackgroundKeepAliveManager / BackupKeepAlive
/// (GPL-3.0); see Resources/Legal/OpenMinis-Notice.md.
@MainActor
@Observable
final class BackgroundExecutionController {
    static let shared = BackgroundExecutionController()

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "via-vera.background-execution")
            refresh()
        }
    }
    private(set) var isKeepingAlive = false
    private(set) var errorMessage: String?
    private var leases: [UUID: () -> Void] = [:]
    private let defaults: UserDefaults
#if os(iOS)
    private var assertion: UIBackgroundTaskIdentifier = .invalid
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observers: [NSObjectProtocol] = []
    private var retryTask: Task<Void, Never>?
    private var foregroundTask: Task<Void, Never>?
    private var isLeavingForeground = false
    private var isInterrupted = false
    private var activationAttempts = 0
#endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "via-vera.background-execution") as? Bool ?? true
    }

    func begin(expiration: @escaping () -> Void) -> UUID {
        let id = UUID()
        leases[id] = expiration
#if os(iOS)
        observeLifecycleIfNeeded()
        beginAssertion()
#endif
        refresh()
        return id
    }

    func end(_ id: UUID) {
        leases.removeValue(forKey: id)
        refresh()
#if os(iOS)
        if leases.isEmpty { endAssertion() }
#endif
    }

    private func refresh() {
#if os(iOS)
        let wantsAudio = isEnabled && !leases.isEmpty && !isInterrupted
            && (isLeavingForeground || UIApplication.shared.applicationState != .active)
        if wantsAudio {
            startAudio()
        } else {
            retryTask?.cancel()
            retryTask = nil
            activationAttempts = 0
            stopAudio()
        }
#endif
    }

#if os(iOS)
    private func observeLifecycleIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        // NotificationCenter delivers UIKit lifecycle notifications synchronously
        // on the main queue. Arm before suspension, without an asynchronous hop.
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.foregroundTask?.cancel()
                    self?.isLeavingForeground = true
                    self?.refresh()
                }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isLeavingForeground = false
                self.foregroundTask?.cancel()
                self.foregroundTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    self?.refresh()
                }
                if !self.leases.isEmpty { self.beginAssertion() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self,
                      let raw,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                self.isInterrupted = type == .began
                self.stopAudio(deactivate: false)
                self.refresh()
                if self.isInterrupted && !self.leases.isEmpty { self.beginAssertion() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopAudio(deactivate: false)
                self?.isInterrupted = false
                self?.refresh()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine?.isRunning == false else { return }
                self.stopAudio(deactivate: false)
                self.refresh()
            }
        })
    }

    private func beginAssertion() {
        guard assertion == .invalid else { return }
        assertion = UIApplication.shared.beginBackgroundTask(withName: "OmniBot task") { [weak self] in
            guard let self else { return }
            self.endAssertion()
            // Expiry of the finite grant must not cancel work while the audio
            // background mode is still effective (an important OpenMinis fix).
            guard self.engine?.isRunning != true || self.player?.isPlaying != true else { return }
            self.errorMessage = String(localized: "系统已结束后台执行时间，任务进度已保留。请回到应用重试。")
            for expire in Array(self.leases.values) { expire() }
        }
    }

    private func endAssertion() {
        let old = assertion
        assertion = .invalid
        if old != .invalid { UIApplication.shared.endBackgroundTask(old) }
    }

    private func startAudio() {
        guard engine?.isRunning != true, retryTask == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let audioEngine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            let frames: AVAudioFrameCount = 44_100
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = buffer.floatChannelData?[0] else {
                throw CocoaError(.coderInvalidValue)
            }
            buffer.frameLength = frames
            samples.initialize(repeating: 0, count: Int(frames))
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
            audioEngine.mainMixerNode.outputVolume = 0.001
            try audioEngine.start()
            node.scheduleBuffer(buffer, at: nil, options: .loops)
            node.play()
            engine = audioEngine
            player = node
            isKeepingAlive = audioEngine.isRunning && node.isPlaying
            activationAttempts = 0
            errorMessage = nil
        } catch {
            stopAudio()
            // Even a partially activated session must be released on failure.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            errorMessage = String(localized: "后台保活暂不可用：\(error.localizedDescription)")
            activationAttempts += 1
            guard activationAttempts < 3 else { return }
            retryTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                self?.retryTask = nil
                self?.refresh()
            }
        }
    }

    private func stopAudio(deactivate: Bool = true) {
        let ownedSession = engine != nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        isKeepingAlive = false
        if ownedSession && deactivate {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
#endif
}
