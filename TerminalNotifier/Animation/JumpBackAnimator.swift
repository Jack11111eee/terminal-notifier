import QuartzCore

class JumpBackAnimator {

    static let duration: CFTimeInterval = 0.6

    /// Animate a layer from its current position to the menu bar position
    /// following a parabolic arc (up then to target), with scale-down.
    func animate(layer: CALayer, from currentPos: CGPoint, to targetPos: CGPoint,
                 completion: @escaping () -> Void) {

        let positionAnim = CAKeyframeAnimation(keyPath: "position")
        let arcHeight: CGFloat = 80
        let mid = NSPoint(
            x: (currentPos.x + targetPos.x) / 2,
            y: max(currentPos.y, targetPos.y) + arcHeight
        )
        positionAnim.values = [currentPos, mid, targetPos].map { NSValue(point: $0) }
        positionAnim.keyTimes = [0.0, 0.4, 1.0]
        positionAnim.duration = Self.duration
        positionAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        positionAnim.fillMode = .forwards
        positionAnim.isRemovedOnCompletion = false

        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [1.0, 0.6, 0.15]
        scaleAnim.keyTimes = [0.0, 0.5, 1.0]
        scaleAnim.duration = Self.duration
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false

        let group = CAAnimationGroup()
        group.animations = [positionAnim, scaleAnim]
        group.duration = Self.duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(group, forKey: "jumpBack")
        CATransaction.commit()
    }
}
