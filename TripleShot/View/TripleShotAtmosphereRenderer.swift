import Foundation

// Port of view/TripleShotAtmosphereRenderer.kt (TripleShotGame dd722e5), statement by statement (spec 06 sections
// 3.6 and 4.12). Drawn in Android device pixels (the host overlay's ACanvas, width/height in px), so 1.8 px snowflakes,
// 15 px streaks and `width / 520` strokes look like the Android device at the iOS screen density. Kotlin types are
// kept: `nowMs` is Long (`Int64`), the integer divisions are Long divisions, `sin` on a Double is Double math and
// kotlin.math `sin` on a Float is computed in Double (ksin). `Paint.alpha` on the light paints modulates their radial
// gradient (AndroidKit APaint/ACanvas, like Skia). The court views construct their own (never drawn) instances, as on
// Android (spec 06 section 4.12); only the host's `weather` instance draws.

/** Lightweight decorative weather/light pass. No gameplay state is read or changed here. */
final class TripleShotAtmosphereRenderer {
    private let paint = APaint(APaint.ANTI_ALIAS_FLAG)
    private var lightWidth = -1
    private var lightHeight = -1
    private var lightRadius: Float = 0
    private var lightPaints: [APaint] = []
    private var lightCenters: [(first: Float, second: Float)] = []

    init() {}

    @discardableResult
    func draw(
        canvas: ACanvas,
        atmosphere: TripleShotCourtAtmosphere,
        width: Int,
        height: Int,
        nowMs: Int64
    ) -> Bool {
        if width <= 0 || height <= 0 { return false }
        switch atmosphere {
        case .NONE:
            return false
        case .LIGHT_RAIN:
            drawRain(canvas: canvas, width: width, height: height, nowMs: nowMs)
            return true
        case .LIGHT_SNOW:
            drawSnow(canvas: canvas, width: width, height: height, nowMs: nowMs)
            return true
        case .COLORED_LIGHTS:
            drawColoredLights(canvas: canvas, width: width, height: height, nowMs: nowMs)
            return true
        }
    }

    /// Kotlin positional call form `draw(canvas, atmosphere, width, height, nowMs)`.
    @discardableResult
    func draw(_ canvas: ACanvas, _ atmosphere: TripleShotCourtAtmosphere, _ width: Int, _ height: Int, _ nowMs: Int64) -> Bool {
        return draw(canvas: canvas, atmosphere: atmosphere, width: width, height: height, nowMs: nowMs)
    }

    private func drawRain(canvas: ACanvas, width: Int, height: Int, nowMs: Int64) {
        paint.shader = nil
        paint.style = APaint.Style.STROKE
        paint.strokeWidth = (width.toFloat() / 520).coerceIn(1.1, 2.2)
        paint.color = AColor.argb(72, 205, 232, 255)
        let speed: Float = height.toFloat() / 820
        for i in kuntil(0, 46) {
            let x: Float = ((i * 137 + 31) % 997).toFloat() / 997 * width.toFloat()
            let phase: Float = ((Int64(i) * 83 + nowMs / 5) % 1000).toFloat() / 1000
            let y: Float = phase * (height.toFloat() + 80) - 40
            let len: Float = 15 + (i % 5).toFloat() * 3
            canvas.drawLine(x, y, x - 5 * speed, y + len * speed, paint)
        }
        paint.style = APaint.Style.FILL
    }

    private func drawSnow(canvas: ACanvas, width: Int, height: Int, nowMs: Int64) {
        paint.shader = nil
        paint.style = APaint.Style.FILL
        for i in kuntil(0, 34) {
            let phase: Float = ((Int64(i) * 97 + nowMs / 13) % 1400).toFloat() / 1400
            let drift: Float = sin(nowMs.toDouble() / 900.0 + i.toDouble() * 0.73).toFloat() * width.toFloat() * 0.018
            let x: Float = (((i * 149 + 67) % 1009).toFloat() / 1009 * width.toFloat() + drift + width.toFloat())
                .truncatingRemainder(dividingBy: width.toFloat())
            let y: Float = phase * (height.toFloat() + 40) - 20
            let radius: Float = 1.8 + (i % 4).toFloat() * 0.75
            paint.color = AColor.argb(105 + (i % 3) * 24, 255, 255, 255)
            canvas.drawCircle(x, y, radius, paint)
        }
    }

    private func ensureColoredLights(width: Int, height: Int) {
        if lightWidth == width && lightHeight == height && lightPaints.count == 3 { return }
        lightWidth = width
        lightHeight = height
        lightRadius = width.toFloat() * 0.34
        lightPaints.removeAll()
        lightCenters.removeAll()

        let specs: [(first: Int, second: Float, third: Float)] = [
            (first: AColor.rgb(255, 70, 170), second: 0.18, third: 0.35),
            (first: AColor.rgb(70, 150, 255), second: 0.82, third: 0.30),
            (first: AColor.rgb(255, 205, 65), second: 0.53, third: 0.63)
        ]
        for (color, x01, y01) in specs {
            let cx: Float = width.toFloat() * x01
            let cy: Float = height.toFloat() * y01
            let p = APaint(APaint.ANTI_ALIAS_FLAG)
            p.shader = ARadialGradient(
                cx,
                cy,
                lightRadius,
                [
                    AColor.argb(46, AColor.red(color), AColor.green(color), AColor.blue(color)),
                    AColor.TRANSPARENT
                ],
                [0, 1],
                ATileMode.CLAMP
            )
            lightCenters.append((first: cx, second: cy))
            lightPaints.append(p)
        }
    }

    private func drawColoredLights(canvas: ACanvas, width: Int, height: Int, nowMs: Int64) {
        ensureColoredLights(width: width, height: height)
        let t: Float = nowMs.toFloat() / 1000
        for (index, lightPaint) in lightPaints.enumerated() {
            lightPaint.alpha = (150 + 70 * ksin(t * (0.55 + index.toFloat() * 0.12) + index.toFloat())).toInt().coerceIn(70, 220)
            let center = lightCenters[index]
            canvas.drawCircle(center.first, center.second, lightRadius, lightPaint)
        }
    }
}
