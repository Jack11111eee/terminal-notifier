import QuartzCore

class DropBounceAnimator {

    static let duration: CFTimeInterval = 1.2
    private static let damping: CGFloat = 4.0
    private static let frequency: CGFloat = 2.5
    private static let keyframeCount = 72

    /// Animate a CALayer from startY to endY with a damped bounce effect.
    func animate(layer: CALayer, from startY: CGFloat, to endY: CGFloat,
                 completion: @escaping () -> Void) {

        let values = Self.generateKeyframes(startY: startY, endY: endY)
        let animation = CAKeyframeAnimation(keyPath: "position.y")
        animation.values = values
        animation.duration = Self.duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(animation, forKey: "drop")
        CATransaction.commit()
    }

    private static func generateKeyframes(startY: CGFloat, endY: CGFloat) -> [CGFloat] {
        var values: [CGFloat] = []
        for i in 0..<keyframeCount {
            let t = CGFloat(i) / CGFloat(keyframeCount - 1)
            let y = endY + (startY - endY) * exp(-damping * t) * cos(2 * .pi * frequency * t)
            values.append(y)
        }
        return values
    }
}
