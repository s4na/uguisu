import Cocoa
import SwiftUI
import Combine

// MARK: - App State

enum VoiceInputState: Equatable {
    case ready
    case recording
    case transcribing
    case preview(text: String)
    case error(message: String)

    static func == (lhs: VoiceInputState, rhs: VoiceInputState) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready),
             (.recording, .recording),
             (.transcribing, .transcribing):
            return true
        case (.preview(let lText), .preview(let rText)):
            return lText == rText
        case (.error(let lMsg), .error(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

// MARK: - View Model

class OverlayViewModel: ObservableObject {
    @Published var state: VoiceInputState = .ready
    @Published var recognizedText: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0

    private var sttEngine: STTEngine?
    private var recordingTimer: Timer?

    var onInsertText: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        setupSTTEngine()
    }

    private func setupSTTEngine() {
        sttEngine = STTEngine()
        sttEngine?.delegate = self
    }

    func startRecording() {
        guard state == .ready else { return }

        state = .recording
        recognizedText = ""
        recordingDuration = 0

        // Start duration timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }

        sttEngine?.startRecognition()
    }

    func stopRecording() {
        guard state == .recording else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil

        state = .transcribing
        sttEngine?.finishRecognition()
    }

    func toggleRecording() {
        switch state {
        case .ready:
            startRecording()
        case .recording:
            stopRecording()
        default:
            break
        }
    }

    func confirmInsertion() {
        guard case .preview(let text) = state, !text.isEmpty else { return }
        onInsertText?(text)
    }

    func cancel() {
        sttEngine?.stopRecognition()
        recordingTimer?.invalidate()
        recordingTimer = nil
        onCancel?()
    }

    func reset() {
        state = .ready
        recognizedText = ""
        audioLevel = 0.0
        recordingDuration = 0.0
    }
}

extension OverlayViewModel: STTEngineDelegate {
    func sttEngineDidStartRecognition() {
        // Already set in startRecording
    }

    func sttEngine(_ engine: STTEngine, didRecognizePartialResult text: String) {
        DispatchQueue.main.async {
            self.recognizedText = text
        }
    }

    func sttEngine(_ engine: STTEngine, didRecognizeFinalResult text: String) {
        DispatchQueue.main.async {
            self.recognizedText = text
            if text.isEmpty {
                self.state = .error(message: "音声が検出されませんでした")
            } else {
                self.state = .preview(text: text)
            }
        }
    }

    func sttEngine(_ engine: STTEngine, didFailWithError error: STTEngineError) {
        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.state = .error(message: error.localizedDescription)
        }
    }
}

// MARK: - Overlay Window

class OverlayWindow: NSWindow {
    weak var viewModel: OverlayViewModel?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape key
            viewModel?.cancel()
            close()
        case 36: // Enter key
            if case .preview = viewModel?.state {
                viewModel?.confirmInsertion()
                close()
            }
        case 49: // Space key
            viewModel?.toggleRecording()
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Window Controller

class OverlayWindowController: NSWindowController {
    private var viewModel = OverlayViewModel()

    convenience init() {
        let viewModel = OverlayViewModel()
        let contentView = OverlayContentView(viewModel: viewModel)

        let window = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 250),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.viewModel = viewModel
        window.contentView = NSHostingView(rootView: contentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.center()
        window.isMovableByWindowBackground = true

        self.init(window: window)
        self.viewModel = viewModel
        setupCallbacks()
    }

    private func setupCallbacks() {
        viewModel.onInsertText = { [weak self] text in
            self?.insertText(text)
        }

        viewModel.onCancel = { [weak self] in
            self?.handleCancel()
        }
    }

    override func showWindow(_ sender: Any?) {
        // Capture focus before showing overlay
        TextInsertionService.shared.captureCurrentFocus()

        // Reset state and show
        viewModel.reset()

        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Auto-start recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.viewModel.startRecording()
        }
    }

    func closeWindow() {
        viewModel.cancel()
        window?.close()
    }

    private func insertText(_ text: String) {
        TextInsertionService.shared.insertText(text) { result in
            switch result {
            case .success:
                print("Text inserted successfully")
            case .clipboardFallbackUsed:
                print("Text inserted via clipboard fallback")
            case .accessibilityDenied:
                print("Accessibility permission denied")
            case .targetNotFound:
                print("Target application not found")
            case .insertionFailed:
                print("Text insertion failed")
            }
        }
        TextInsertionService.shared.clearFocus()
    }

    private func handleCancel() {
        TextInsertionService.shared.clearFocus()
    }
}

// MARK: - Content View

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            statusView

            // Main content area
            contentArea

            // Help text
            helpText
        }
        .frame(width: 600, height: 250)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
    }

    @ViewBuilder
    private var statusView: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .animation(.easeInOut(duration: 0.3), value: viewModel.state)

            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            if case .recording = viewModel.state {
                Text(formatDuration(viewModel.recordingDuration))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .ready:
            return .gray
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .preview:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .ready:
            return "準備完了"
        case .recording:
            return "録音中..."
        case .transcribing:
            return "変換中..."
        case .preview:
            return "確認"
        case .error:
            return "エラー"
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 8) {
            switch viewModel.state {
            case .ready:
                Text("Spaceキーで録音開始")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.primary)

            case .recording:
                if viewModel.recognizedText.isEmpty {
                    Text("話してください...")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    ScrollView {
                        Text(viewModel.recognizedText)
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Audio level indicator
                AudioLevelView(level: viewModel.audioLevel)
                    .frame(height: 4)
                    .padding(.horizontal, 40)

            case .transcribing:
                ProgressView()
                    .scaleEffect(1.5)
                Text("音声を変換中...")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)

            case .preview(let text):
                ScrollView {
                    Text(text)
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var helpText: some View {
        HStack(spacing: 16) {
            switch viewModel.state {
            case .ready:
                KeyHint(key: "Space", action: "録音開始")
                KeyHint(key: "Esc", action: "キャンセル")

            case .recording:
                KeyHint(key: "Space", action: "録音停止")
                KeyHint(key: "Esc", action: "キャンセル")

            case .preview:
                KeyHint(key: "Enter", action: "入力")
                KeyHint(key: "Esc", action: "キャンセル")

            case .transcribing, .error:
                KeyHint(key: "Esc", action: "キャンセル")
            }
        }
        .padding(.bottom, 16)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration - Double(Int(duration))) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Helper Views

struct KeyHint: View {
    let key: String
    let action: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                )
            Text(action)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.3))
                .overlay(
                    HStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: geometry.size.width * CGFloat(level))
                        Spacer(minLength: 0)
                    }
                )
        }
    }
}
