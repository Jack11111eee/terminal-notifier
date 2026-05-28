import AppKit

class SoundManager {
    private var sound: NSSound?

    func playNotificationSound() {
        guard PreferencesManager.shared.soundEnabled else { return }
        if sound == nil {
            sound = NSSound(named: "notify")
        }
        sound?.stop()
        sound?.play()
    }
}
