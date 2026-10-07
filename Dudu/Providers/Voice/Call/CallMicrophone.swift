import AVFoundation
import Foundation

// MARK: - Call microphone (full-duplex)
//
// One AVAudioEngine input tap serving two jobs, mirroring the old Dudu's
// single-recorder design (monitor metering + segment file):
//   (a) live dB levels → the energy VAD and the waveform UI, always on;
//   (b) while capturing, PCM accumulates; stopCapture() returns it as a
//       16-bit mono WAV for STT.
//
// The audio SESSION is owned by AudioSessionCoordinator (the `.voiceCall`
// intent → .playAndRecord/.voiceChat). This class only taps the input node,
// so it never fights the coordinator's category ownership.
//
// Threading: the tap runs on a realtime audio thread. Level callbacks hop
// to the main queue; capture state is guarded by `lock`.

final class CallMicrophone {

    /// Live mic level in dB (negative; silence ≈ -70, speech ≈ -45..-10).
    /// Set once before start(); always called on the main queue.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var capturing = false
    private var captureSamples: [Float] = []
    private var sampleRate: Double = 48_000
    private var observersRegistered = false

    private(set) var isRunning = false

    private let logger = AppLogger(category: "CallMic")

    deinit {
        unregisterObservers()
    }

    // MARK: - Control

    /// Begin metering. The caller must have the `.voiceCall` session intent
    /// active already (so the input node reports a real format).
    func start() throws {
        guard !isRunning else { return }
        let inputNode = engine.inputNode
        // Use the node's INPUT bus format — outputFormat(forBus:) can disagree
        // with the tap-able format after a route change and installTap throws.
        let format = inputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate
        logger.info("installTap: format=\(format.channelCount)ch \(Int(sampleRate))Hz")
        guard format.channelCount > 0, sampleRate > 0 else {
            throw VoiceProviderError.parseError("Microphone input unavailable")
        }
        let installed = DuduCatchObjCException({
            inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }
        }, nil)
        guard installed else {
            throw VoiceProviderError.parseError("Failed to attach microphone tap")
        }
        engine.prepare()
        var startError: Error?
        let started = DuduCatchObjCException({
            do { try self.engine.start() } catch { startError = error }
        }, nil)
        guard started, startError == nil else {
            engine.stop()
            inputNode.removeTap(onBus: 0)
            throw startError ?? VoiceProviderError.parseError("Audio engine failed to start")
        }
        isRunning = true
        registerObservers()
        logger.info("call mic started")
    }

    func stop() {
        guard isRunning else { return }
        tearDown()
        logger.info("call mic stopped")
    }

    /// Begin accumulating the current utterance. Levels keep flowing.
    func startCapture() {
        lock.lock()
        capturing = true
        captureSamples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// Stop accumulating and return the utterance as a 16-bit mono WAV.
    /// nil when nothing usable was captured.
    func stopCapture() -> Data? {
        lock.lock()
        capturing = false
        let samples = captureSamples
        let rate = sampleRate
        captureSamples.removeAll(keepingCapacity: true)
        lock.unlock()
        guard Double(samples.count) / rate > 0.2 else { return nil }
        return Self.wavData(fromFloatSamples: samples, sampleRate: rate)
    }

    /// Abandon the in-progress capture.
    func cancelCapture() {
        lock.lock()
        capturing = false
        captureSamples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    // MARK: - Tap

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let mono = channelData[0]

        var sum: Float = 0
        for i in 0..<frames {
            let s = mono[i]
            sum += s * s
        }
        let rms = sqrtf(sum / Float(frames))
        // dBFS, floored so silence reads ≈ -80 instead of -inf.
        let db = max(-80, 20 * log10(max(rms, 1e-4)))
        let cb = onLevel
        DispatchQueue.main.async { cb?(db) }

        lock.lock()
        let isCapturing = capturing
        if isCapturing {
            captureSamples.append(contentsOf: UnsafeBufferPointer(start: mono, count: frames))
        }
        lock.unlock()
    }

    // MARK: - WAV

    /// Encode mono Float32 samples to 16-bit PCM WAV at the tap's sample rate.
    static func wavData(fromFloatSamples samples: [Float], sampleRate: Double) -> Data? {
        guard !samples.isEmpty else { return nil }
        var pcm16 = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, samples[i]))
            pcm16[i] = Int16(clamped * 32767)
        }
        let pcmData = pcm16.withUnsafeBytes { Data($0) }
        let dataSize = UInt32(pcmData.count)
        let sr = UInt32(sampleRate)
        var wav = Data()
        func appendLE32(_ v: UInt32) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 4)) }
        func appendLE16(_ v: UInt16) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 2)) }
        wav.append("RIFF".data(using: .ascii)!)
        appendLE32(36 + dataSize)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        appendLE32(16)
        appendLE16(1)   // PCM
        appendLE16(1)   // mono
        appendLE32(sr)
        appendLE32(sr * 2)
        appendLE16(2)
        appendLE16(16)
        wav.append("data".data(using: .ascii)!)
        appendLE32(dataSize)
        wav.append(pcmData)
        return wav
    }

    // MARK: - Interruption recovery

    private func tearDown() {
        unregisterObservers()
        engine.stop()
        _ = DuduCatchObjCException({ self.engine.inputNode.removeTap(onBus: 0) }, nil)
        lock.lock()
        capturing = false
        captureSamples.removeAll(keepingCapacity: true)
        lock.unlock()
        isRunning = false
    }

    private func registerObservers() {
        guard !observersRegistered else { return }
        observersRegistered = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    private func unregisterObservers() {
        guard observersRegistered else { return }
        observersRegistered = false
        NotificationCenter.default.removeObserver(
            self, name: AVAudioSession.interruptionNotification, object: nil)
    }

    /// A system interruption (phone call / Siri) stops the engine. When it
    /// ends, rebuild the tap if the call is still running — otherwise the
    /// mic would die silently mid-call.
    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isRunning, !engine.isRunning {
                logger.info("interruption began — engine stopped")
            }
        case .ended:
            guard isRunning, !engine.isRunning else { return }
            logger.info("interruption ended — rebuilding mic tap")
            tearDownEngineOnly()
            do {
                try start()
            } catch {
                logger.error("mic resume failed: \(error.localizedDescription)")
            }
        @unknown default:
            break
        }
    }

    private func tearDownEngineOnly() {
        engine.stop()
        _ = DuduCatchObjCException({ self.engine.inputNode.removeTap(onBus: 0) }, nil)
        // Keep observers + capture state: the resume rebuilds around them.
        // Temporarily clear isRunning so start() proceeds.
        isRunning = false
    }
}
