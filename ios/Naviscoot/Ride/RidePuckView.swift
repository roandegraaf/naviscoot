import UIKit

// A plain view over the map rather than a map layer: it moves every frame, and a symbol layer would be laid out and
// faded in again on each of those updates.
final class RidePuckView: UIView {
    static let haloRadius: CGFloat = 24

    private let halo = UIView()
    private let arrow = UIImageView(image: RidePuckView.image)
    private var placed: (point: CGPoint, angle: Double, pitch: Double)?

    init() {
        let side = Self.haloRadius * 2
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        isUserInteractionEnabled = false
        isHidden = true
        halo.frame = bounds
        halo.layer.cornerRadius = Self.haloRadius
        arrow.center = CGPoint(x: side / 2, y: side / 2)
        addSubview(halo)
        addSubview(arrow)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    var haloColor: UIColor? {
        get { halo.backgroundColor }
        set { halo.backgroundColor = newValue }
    }

    func place(at point: CGPoint, screenAngle: Double, pitch: Double) {
        if let placed, abs(placed.point.x - point.x) < 0.05, abs(placed.point.y - point.y) < 0.05,
           abs(placed.angle - screenAngle) < 0.1, abs(placed.pitch - pitch) < 0.1, !isHidden { return }
        placed = (point, screenAngle, pitch)
        isHidden = false
        center = point
        arrow.transform = CGAffineTransform(rotationAngle: screenAngle * .pi / 180)
            .concatenating(CGAffineTransform(scaleX: 1, y: cos(pitch * .pi / 180)))
    }

    static let image: UIImage = {
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            UIColor.white.setFill()
            UIBezierPath(arcCenter: center, radius: 20, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            Theme.verifiedUI.setFill()
            UIBezierPath(arcCenter: center, radius: 16.5, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: center.x, y: center.y - 11))
            arrow.addLine(to: CGPoint(x: center.x + 8.5, y: center.y + 9))
            arrow.addLine(to: CGPoint(x: center.x, y: center.y + 4.5))
            arrow.addLine(to: CGPoint(x: center.x - 8.5, y: center.y + 9))
            arrow.close()
            UIColor.white.setFill()
            arrow.fill()
        }
    }()
}

final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let onFrame: @MainActor (CFTimeInterval) -> Bool

    init(onFrame: @escaping @MainActor (CFTimeInterval) -> Bool) {
        self.onFrame = onFrame
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let time = link.targetTimestamp
        let keepGoing = MainActor.assumeIsolated { onFrame(time) }
        if !keepGoing { stop() }
    }
}
