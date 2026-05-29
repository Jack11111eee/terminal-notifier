import AppKit

class SoundManager {
    private var sound: NSSound?

    func playNotificationSound() {
        guard PreferencesManager.shared.soundEnabled else { return }
        if sound == nil {
            sound = NSSound(named: "Glass")
        }
        guard let sound else {
            NSSound.beep()
            return
        }
        sound.stop()
        sound.play()
    }
}
