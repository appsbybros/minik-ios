import UIKit

@MainActor
private final class LoadingFrameTarget: NSObject {
    weak var view: BattleLoadingView?

    @objc func tick(_ link: CADisplayLink) {
        guard let view = view else {
            link.invalidate()
            return
        }
        view.setNeedsDisplay()
    }
}

/// Port of Android BattleLoadingView.kt: drawn immediately while the arena ground loads, then
/// faded after its first real frame. The lagoon, the player's avatar with Minik and Mia, and
/// five bouncing balloons (one of three motions). As on Android, the portraits and balloons
/// are drawn with the overlay paint's alpha (0x8c).
@MainActor
final class BattleLoadingView: UIView {
    private let art: ArtStore
    private let avatar: String
    private let start = SplashClock.uptimeMillis()
    private let variation: Int
    private var link: CADisplayLink?
    private let target = LoadingFrameTarget()

    init(art: ArtStore, avatar: String) {
        self.art = art
        self.avatar = avatar
        self.variation = Int(start % 3)
        super.init(frame: .zero)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
        backgroundColor = SplashPalette.ui(0xff103550)
        target.view = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimating()
        } else if link == nil {
            let made = CADisplayLink(target: target, selector: #selector(LoadingFrameTarget.tick(_:)))
            made.add(to: .main, forMode: .common)
            link = made
        }
    }

    func stopAnimating() {
        link?.invalidate()
        link = nil
    }

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let width = bounds.width
        let height = bounds.height
        c.setFillColor(SplashPalette.ui(0xff103550).cgColor)
        c.fill(bounds)
        art.lagoon?.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        c.setFillColor(SplashPalette.ui(0x8c0b2440).cgColor)
        c.fill(bounds)
        let alpha = CGFloat(0x8c) / 255
        let t = CGFloat((SplashClock.uptimeMillis() - start) % 1200) / 1200
        var ids: [String] = []
        for id in [avatar, "minik", "mia"] where !ids.contains(id) { ids.append(id) }
        let size = min(width * 0.28, height * 0.42)
        for (i, id) in ids.enumerated() {
            let x = width * CGFloat(i + 1) / CGFloat(ids.count + 1)
            art.portrait(id)?.draw(in: CGRect(x: x - size / 2, y: height * 0.68 - size * 1.25, width: size, height: size * 1.25),
                                   blendMode: .normal, alpha: alpha)
        }
        for i in 0...4 {
            let phase = (t + CGFloat(i) * 0.18).truncatingRemainder(dividingBy: 1)
            let x = variation == 2 ? width * (0.1 + 0.8 * phase) : width * CGFloat(i + 1) / 6
            let y = height * (0.65 - 0.45 * CGFloat(sin(Double(phase) * Double.pi)))
            let w = width * (0.055 + (variation == 0 ? phase * 0.15 : 0))
            art.balloon(i)?.draw(in: CGRect(x: x - w / 2, y: y - w, width: w, height: w), blendMode: .normal, alpha: alpha)
        }
    }
}
