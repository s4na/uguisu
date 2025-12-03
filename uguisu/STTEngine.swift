import Foundation
import Speech
import AVFoundation

protocol STTEngineDelegate: AnyObject {
    func sttEngineDidStartRecognition()
    func sttEngine(_ engine: STTEngine, didRecognizePartialResult text: String)
    func sttEngine(_ engine: STTEngine, didRecognizeFinalResult text: String)
    func sttEngine(_ engine: STTEngine, didFailWithError error: STTEngineError)
}

enum STTEngineError: Error, LocalizedError {
    case speechRecognitionPermissionDenied
    case speechRecognitionNotAvailable
    case recognitionFailed(String)
    case audioEngineError(String)
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .speechRecognitionPermissionDenied:
            return "Speech recognition permission was denied. Please grant permission in System Preferences."
        case .speechRecognitionNotAvailable:
            return "Speech recognition is not available on this device."
        case .recognitionFailed(let message):
            return "Speech recognition failed: \(message)"
        case .audioEngineError(let message):
            return "Audio engine error: \(message)"
        case .noSpeechDetected:
            return "No speech was detected."
        }
    }
}

class STTEngine {
    weak var delegate: STTEngineDelegate?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    private var isRecognizing = false
    private var lastRecognizedText = ""

    // Default to Japanese locale, can be changed
    var locale: Locale = Locale(identifier: "ja-JP") {
        didSet {
            speechRecognizer = SFSpeechRecognizer(locale: locale)
        }
    }

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    deinit {
        stopRecognition()
    }

    func requestSpeechRecognitionPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func startRecognition() {
        guard !isRecognizing else { return }

        // Check speech recognition availability
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            delegate?.sttEngine(self, didFailWithError: .speechRecognitionNotAvailable)
            return
        }

        // Request permission
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.setupAndStartRecognition()
                case .denied, .restricted, .notDetermined:
                    self.delegate?.sttEngine(self, didFailWithError: .speechRecognitionPermissionDenied)
                @unknown default:
                    self.delegate?.sttEngine(self, didFailWithError: .speechRecognitionPermissionDenied)
                }
            }
        }
    }

    private func setupAndStartRecognition() {
        do {
            // Cancel any existing task
            recognitionTask?.cancel()
            recognitionTask = nil

            // Create audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }

            request.shouldReportPartialResults = true

            // For on-device recognition (iOS 13+ / macOS 10.15+)
            if #available(macOS 10.15, *) {
                request.requiresOnDeviceRecognition = false
            }

            // Start recognition task
            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    // Check if it's just the recognition ending
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        // Recognition ended normally, finalize the text
                        if !self.lastRecognizedText.isEmpty {
                            self.delegate?.sttEngine(self, didRecognizeFinalResult: self.lastRecognizedText)
                        } else {
                            self.delegate?.sttEngine(self, didFailWithError: .noSpeechDetected)
                        }
                    } else {
                        self.delegate?.sttEngine(self, didFailWithError: .recognitionFailed(error.localizedDescription))
                    }
                    return
                }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.lastRecognizedText = text

                    if result.isFinal {
                        self.delegate?.sttEngine(self, didRecognizeFinalResult: text)
                    } else {
                        self.delegate?.sttEngine(self, didRecognizePartialResult: text)
                    }
                }
            }

            // Install tap on audio input
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecognizing = true
            lastRecognizedText = ""

            delegate?.sttEngineDidStartRecognition()

        } catch {
            delegate?.sttEngine(self, didFailWithError: .audioEngineError(error.localizedDescription))
        }
    }

    func stopRecognition() {
        guard isRecognizing else { return }

        isRecognizing = false

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
    }

    /// Finalize recognition and get the result
    func finishRecognition() {
        guard isRecognizing else { return }

        // End the audio input to trigger final result
        recognitionRequest?.endAudio()

        // Give a short delay for final processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            if !self.lastRecognizedText.isEmpty {
                self.delegate?.sttEngine(self, didRecognizeFinalResult: self.lastRecognizedText)
            }

            self.stopRecognition()
        }
    }
}
