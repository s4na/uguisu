import AVFoundation
import Foundation

protocol AudioEngineDelegate: AnyObject {
    func audioEngineDidStartRecording()
    func audioEngineDidStopRecording()
    func audioEngine(_ engine: AudioEngine, didReceiveAudioLevel level: Float)
    func audioEngine(_ engine: AudioEngine, didFailWithError error: AudioEngineError)
}

enum AudioEngineError: Error, LocalizedError {
    case microphonePermissionDenied
    case audioSessionSetupFailed(String)
    case engineStartFailed(String)
    case recordingTimeout

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please grant permission in System Preferences."
        case .audioSessionSetupFailed(let message):
            return "Failed to setup audio session: \(message)"
        case .engineStartFailed(let message):
            return "Failed to start audio engine: \(message)"
        case .recordingTimeout:
            return "Recording reached the maximum time limit."
        }
    }
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: AVAudioPCMBuffer?
    private var recordedBuffers: [AVAudioPCMBuffer] = []

    private var isRecording = false
    private var recordingStartTime: Date?
    private var timeoutTimer: Timer?

    // Recording settings
    static let sampleRate: Double = 16000.0
    static let maxRecordingDuration: TimeInterval = 60.0
    static let warningDuration: TimeInterval = 50.0

    var currentRecordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    init() {}

    deinit {
        stopRecording()
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }

            if granted {
                self.setupAndStartRecording()
            } else {
                self.delegate?.audioEngine(self, didFailWithError: .microphonePermissionDenied)
            }
        }
    }

    private func setupAndStartRecording() {
        do {
            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }

            inputNode = engine.inputNode
            guard let inputNode = inputNode else { return }

            // Get the native format and convert to 16kHz mono for STT
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Create a format for 16kHz mono PCM
            guard let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                delegate?.audioEngine(self, didFailWithError: .audioSessionSetupFailed("Failed to create audio format"))
                return
            }

            // Install tap on input node
            let bufferSize: AVAudioFrameCount = 1024

            // Use a converter if sample rates don't match
            let converter = AVAudioConverter(from: inputFormat, to: recordingFormat)

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self, self.isRecording else { return }

                // Convert to target format if needed
                if let converter = converter {
                    let frameCapacity = AVAudioFrameCount(
                        Double(buffer.frameLength) * Self.sampleRate / inputFormat.sampleRate
                    )
                    guard let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: recordingFormat,
                        frameCapacity: frameCapacity
                    ) else { return }

                    var error: NSError?
                    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }

                    converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

                    if error == nil {
                        self.recordedBuffers.append(convertedBuffer)
                        self.updateAudioLevel(buffer: buffer)
                    }
                } else {
                    self.recordedBuffers.append(buffer)
                    self.updateAudioLevel(buffer: buffer)
                }
            }

            engine.prepare()
            try engine.start()

            isRecording = true
            recordingStartTime = Date()
            recordedBuffers.removeAll()

            // Start timeout timer
            startTimeoutTimer()

            DispatchQueue.main.async {
                self.delegate?.audioEngineDidStartRecording()
            }

        } catch {
            delegate?.audioEngine(self, didFailWithError: .engineStartFailed(error.localizedDescription))
        }
    }

    func stopRecording() -> Data? {
        guard isRecording else { return nil }

        isRecording = false
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        let audioData = combineBuffersToData()

        recordedBuffers.removeAll()
        recordingStartTime = nil

        DispatchQueue.main.async {
            self.delegate?.audioEngineDidStopRecording()
        }

        return audioData
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0

        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }

        let average = sum / Float(frameLength)
        let level = min(1.0, average * 10) // Normalize to 0-1 range

        DispatchQueue.main.async {
            self.delegate?.audioEngine(self, didReceiveAudioLevel: level)
        }
    }

    private func startTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.audioEngine(self, didFailWithError: .recordingTimeout)
            _ = self.stopRecording()
        }
    }

    private func combineBuffersToData() -> Data {
        guard !recordedBuffers.isEmpty else { return Data() }

        // Calculate total frame count
        let totalFrames = recordedBuffers.reduce(0) { $0 + Int($1.frameLength) }

        // Create combined buffer
        var audioData = Data()

        for buffer in recordedBuffers {
            guard let channelData = buffer.floatChannelData?[0] else { continue }
            let frameLength = Int(buffer.frameLength)

            // Convert float samples to Data
            let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
            audioData.append(data)
        }

        return audioData
    }
}
