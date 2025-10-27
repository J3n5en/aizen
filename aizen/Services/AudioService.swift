import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
class AudioService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var partialTranscription = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionStatus: PermissionStatus = .notDetermined

    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
    }

    private var audioRecorder: AVAudioRecorder?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var levelTimer: Timer?

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Permission Handling

    func requestPermissions() async -> Bool {
        let micPermission = await requestMicrophonePermission()
        let speechPermission = await requestSpeechPermission()

        let granted = micPermission && speechPermission
        permissionStatus = granted ? .authorized : .denied
        return granted
    }

    private func requestMicrophonePermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func requestSpeechPermission() async -> Bool {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()

        if currentStatus == .authorized {
            return true
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func checkPermissions() async -> Bool {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()

        let granted = micStatus == .authorized && speechStatus == .authorized
        let notDetermined = micStatus == .notDetermined || speechStatus == .notDetermined
        permissionStatus = granted ? .authorized : (notDetermined ? .notDetermined : .denied)
        return granted
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        let hasPermissions = await checkPermissions()
        if !hasPermissions {
            let granted = await requestPermissions()
            guard granted else {
                throw RecordingError.permissionDenied
            }
        }

        // Reset state
        transcribedText = ""
        partialTranscription = ""
        audioLevel = 0.0
        recordingDuration = 0

        try await startSpeechRecognition()

        isRecording = true
        recordingStartTime = Date()

        startDurationTimer()
        startLevelMonitoring()
    }

    func stopRecording() async -> String {
        isRecording = false

        // Stop timers
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        // Stop speech recognition
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil

        // Wait a moment for final transcription
        try? await Task.sleep(for: .milliseconds(500))

        let finalText = transcribedText.isEmpty ? partialTranscription : transcribedText

        // Reset state
        transcribedText = ""
        partialTranscription = ""
        audioLevel = 0.0
        recordingDuration = 0

        return finalText
    }

    func cancelRecording() {
        isRecording = false

        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil

        transcribedText = ""
        partialTranscription = ""
        audioLevel = 0.0
        recordingDuration = 0
    }

    // MARK: - Speech Recognition

    private func startSpeechRecognition() async throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw RecordingError.speechRecognitionUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = recognitionRequest
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw RecordingError.recordingFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, when in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            throw RecordingError.recordingFailed
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcription = result.bestTranscription.formattedString

                Task { @MainActor in
                    if result.isFinal {
                        self.transcribedText = transcription
                    } else {
                        self.partialTranscription = transcription
                    }
                }
            }

            if error != nil || result?.isFinal == true {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)
            }
        }
    }

    // MARK: - Monitoring

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Simulate audio level (in real implementation, you'd get this from AVAudioRecorder metering)
                self.audioLevel = Float.random(in: 0.3...0.9)
            }
        }
    }

    // MARK: - Errors

    enum RecordingError: LocalizedError {
        case permissionDenied
        case speechRecognitionUnavailable
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Speech Recognition permission is required. The microphone will be automatically requested when recording starts."
            case .speechRecognitionUnavailable:
                return "Speech recognition is not available. Please enable Siri in System Settings > Siri & Spotlight."
            case .recordingFailed:
                return "Failed to start recording. Please check microphone permissions in System Settings > Privacy & Security > Microphone."
            }
        }
    }
}
