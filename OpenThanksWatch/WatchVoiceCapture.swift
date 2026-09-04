import AVFoundation
import Foundation

/// On-watch mic capture. System text input can't be forced to dictation (watchOS
/// remembers the last keyboard/scribble mode), so we record audio ourselves and
/// let the iPhone transcribe + save.
@MainActor
final class WatchVoiceCapture: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?

    var isRecording: Bool { recorder?.isRecording == true }

    func prepareSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func start() throws {
        stopDiscarding()
        try prepareSession()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openthanks-watch-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw CaptureError.couldNotStart
        }
        self.recorder = recorder
        self.fileURL = url
    }

    /// Stops and returns the recorded file URL (nil if nothing useful was captured).
    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil
        let url = fileURL
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        // Tiny files are usually accidental taps / silence.
        if size < 800 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    func stopDiscarding() {
        recorder?.stop()
        recorder = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    enum CaptureError: LocalizedError {
        case couldNotStart
        case micDenied

        var errorDescription: String? {
            switch self {
            case .couldNotStart: return "Couldn't start the microphone."
            case .micDenied: return "Allow microphone access in Settings on Apple Watch."
            }
        }
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
