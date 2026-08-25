import Foundation
import AVFoundation
import AppKit

/// Central manager orchestrating Text-to-Speech synthesis and playback.
/// Supports both Microsoft Edge Neural TTS and macOS System Native Synthesizer.
final class TTSManager: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = TTSManager()

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentPlayingText: String? = nil
    @Published private(set) var currentEngine: TTSEngine = .edgeNeural

    private var audioPlayer: AVAudioPlayer?
    private var nativeSynthesizer = AVSpeechSynthesizer()
    private var currentTask: Task<Void, Never>?

    override private init() {
        super.init()
        nativeSynthesizer.delegate = self
    }

    /// Speaks text using the specified engine, language, and speed rate.
    func speak(text: String,
               language: AppLanguage,
               engine: TTSEngine,
               rate: Double = 1.0) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        // If already playing the same text, stop it (toggle behavior)
        if isPlaying && currentPlayingText == cleanText {
            stop()
            return
        }

        stop()
        currentPlayingText = cleanText
        currentEngine = engine

        switch engine {
        case .edgeNeural:
            speakWithEdgeNeural(text: cleanText, language: language, rate: rate)
        case .systemNative:
            speakWithNativeSynthesizer(text: cleanText, language: language, rate: rate)
        }
    }

    /// Immediately halts any ongoing speech synthesis or audio playback.
    func stop() {
        currentTask?.cancel()
        currentTask = nil

        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil

        if nativeSynthesizer.isSpeaking {
            nativeSynthesizer.stopSpeaking(at: .immediate)
        }

        DispatchQueue.main.async {
            self.isPlaying = false
            self.isLoading = false
            self.currentPlayingText = nil
        }
    }

    /// Previews audio with a sample sentence for the specified language and settings.
    func preview(engine: TTSEngine, rate: Double, language: AppLanguage) {
        let sampleText: String
        switch language {
        case .simplifiedChinese:
            sampleText = "欢迎使用 Glance 屏幕即时翻译。"
        case .traditionalChinese:
            sampleText = "歡迎使用 Glance 螢幕即時翻譯。"
        case .japanese:
            sampleText = "Glance へようこそ。画面上のテキストを即座に翻訳します。"
        case .korean:
            sampleText = "Glance에 오신 것을 환영합니다. 빠른 화면 번역 도구입니다。"
        case .french:
            sampleText = "Bienvenue sur Glance. Traduction instantanée à l'écran."
        case .german:
            sampleText = "Willkommen bei Glance. Schnelle Bildschirmübersetzung."
        case .spanish:
            sampleText = "Bienvenido a Glance. Traducción rápida en pantalla."
        case .english:
            sampleText = "Welcome to Glance. Fast on-screen translation and capture."
        }
        speak(text: sampleText, language: language, engine: engine, rate: rate)
    }

    // MARK: - Private Implementations

    private func speakWithEdgeNeural(text: String, language: AppLanguage, rate: Double) {
        let voice = TTSEngine.defaultVoice(for: language)

        DispatchQueue.main.async {
            self.isLoading = true
            self.isPlaying = false
        }

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let mp3Data = try await EdgeTTSClient.synthesize(text: text, voice: voice, rate: rate)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    do {
                        self.audioPlayer = try AVAudioPlayer(data: mp3Data)
                        self.audioPlayer?.delegate = self
                        self.audioPlayer?.prepareToPlay()
                        self.audioPlayer?.play()
                        self.isLoading = false
                        self.isPlaying = true
                        NSLog("[Glance TTS] Playing Edge Neural audio (%ld bytes, voice: %@)", mp3Data.count, voice)
                    } catch {
                        NSLog("[Glance TTS] AVAudioPlayer error: %@, falling back to native", error.localizedDescription)
                        self.speakWithNativeSynthesizer(text: text, language: language, rate: rate)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                NSLog("[Glance TTS] Edge Neural error: %@, falling back to native", error.localizedDescription)
                await MainActor.run {
                    self.speakWithNativeSynthesizer(text: text, language: language, rate: rate)
                }
            }
        }
    }

    private func speakWithNativeSynthesizer(text: String, language: AppLanguage, rate: Double) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.isPlaying = true
        }

        let utterance = AVSpeechUtterance(string: text)
        let bcp47 = TTSEngine.bcp47Locale(for: language)
        utterance.voice = AVSpeechSynthesisVoice(language: bcp47)

        // Map 0.5 - 1.5 multiplier to AVSpeechUtterance rate
        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let mappedRate = Float(rate) * baseRate
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, mappedRate))

        nativeSynthesizer.speak(utterance)
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isLoading = false
            self.currentPlayingText = nil
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isLoading = false
            self.currentPlayingText = nil
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isLoading = false
            self.currentPlayingText = nil
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isLoading = false
            self.currentPlayingText = nil
        }
    }
}
