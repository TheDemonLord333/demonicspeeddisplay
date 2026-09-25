//
//  OverspeedAnnouncer.swift
//  Demonic Speed Display
//
//  Optionaler, kurzer Sprachhinweis bei Überschreitung. Andere Audioquellen
//  (Musik, Navigation) werden nur kurz abgesenkt und danach wieder freigegeben.
//

import AVFoundation
import Foundation

final class OverspeedAnnouncer {
    /// Mindestabstand zwischen zwei Hinweisen, damit nichts nervt.
    var minimumInterval: TimeInterval = 30

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechDelegate()
    private var lastAnnouncement = Date.distantPast

    init() {
        synthesizer.delegate = delegate
    }

    func announce(now: Date = Date()) {
        guard now.timeIntervalSince(lastAnnouncement) >= minimumInterval,
              !synthesizer.isSpeaking else { return }
        lastAnnouncement = now

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        let utterance = AVSpeechUtterance(string: "Tempolimit")
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        synthesizer.speak(utterance)
    }
}

nonisolated private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Self.releaseAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Self.releaseAudioSession()
    }

    private static func releaseAudioSession() {
        // Abgesenkte Musik wieder auf volle Lautstärke bringen.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
