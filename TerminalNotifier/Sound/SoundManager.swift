import AppKit

class SoundManager {
    private var sound: NSSound?
    private var confirmSound: NSSound?

    func playNotificationSound() {
        playNotificationSound(for: .newNotification)
    }

    /// 按提醒类别分级：需确认类用更引人注目的 Funk，其余沿用温和的 Glass。
    func playNotificationSound(for category: MessageProvider.Category) {
        guard PreferencesManager.shared.soundEnabled else { return }
        switch category {
        case .needsConfirm, .codexNeedsConfirm:
            if confirmSound == nil {
                confirmSound = NSSound(named: "Funk")
            }
            guard let confirmSound else {
                NSSound.beep()
                return
            }
            confirmSound.stop()
            confirmSound.play()
        default:
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
}
