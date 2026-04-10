import SwiftUI
import Level5IslandCore

/// Pixel-art woman character — face-portrait bust, three animation states.
/// Keeps the `ClawdView` name so MascotView.swift / NotchPanelView.swift need no changes.
struct ClawdView: View {
    let status: AgentStatus
    var size: CGFloat = 27
    @State private var alive = false
    @Environment(\.mascotSpeed) private var speed

    // ── Color palette ──
    private static let skinC  = Color(red: 0.949, green: 0.773, blue: 0.627) // #F2C5A0 warm peach
    private static let hairC  = Color(red: 0.478, green: 0.310, blue: 0.180) // #7A4F2E brown
    private static let browC  = Color(red: 0.310, green: 0.196, blue: 0.118) // #4F3220 dark brow
    private static let eyeC   = Color(red: 0.10,  green: 0.06,  blue: 0.04)  // near-black eye
    private static let lipC   = Color(red: 0.851, green: 0.502, blue: 0.451) // #D98073 rose lip
    private static let teethC = Color.white
    private static let alertC = Color(red: 1.0,   green: 0.24,  blue: 0.0)   // #FF3D00
    private static let kbBase = Color(red: 0.38,  green: 0.44,  blue: 0.50)
    private static let kbKey  = Color(red: 0.60,  green: 0.66,  blue: 0.72)
    private static let kbHi   = Color.white

    // Pre-computed angular frequencies (2π/period) used every frame in work scene
    private static let freqBounce: Double = 2 * .pi / 0.35
    private static let freqBreathe: Double = 2 * .pi / 3.2
    private static let freqArmL: Double = 2 * .pi / 0.15
    private static let freqArmR: Double = 2 * .pi / 0.12

    var body: some View {
        ZStack {
            switch status {
            case .idle:                               sleepScene
            case .processing, .running, .compacting:  workScene
            case .waitingApproval, .waitingQuestion:  alertScene
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear { alive = true }
        .onChange(of: status) {
            alive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { alive = true }
        }
    }

    // ── Coordinate helper ──
    private struct V {
        let ox: CGFloat, oy: CGFloat, s: CGFloat, y0: CGFloat

        init(_ sz: CGSize, svgW: CGFloat = 13, svgH: CGFloat = 14, svgY0: CGFloat = 6) {
            s  = min(sz.width / svgW, sz.height / svgH)
            ox = (sz.width  - svgW * s) / 2
            oy = (sz.height - svgH * s) / 2
            y0 = svgY0
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dy: CGFloat = 0) -> CGRect {
            CGRect(x: ox + x * s, y: oy + (y - y0 + dy) * s, width: w * s, height: h * s)
        }
    }

    // ── Rotated arm path ──
    private func armPath(_ v: V, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                         pivotX: CGFloat, pivotY: CGFloat, angle: CGFloat, dy: CGFloat) -> Path {
        let a = angle * .pi / 180
        let ca = cos(a), sa = sin(a)
        let corners: [(CGFloat, CGFloat)] = [
            (x - pivotX, y - pivotY),
            (x + w - pivotX, y - pivotY),
            (x + w - pivotX, y + h - pivotY),
            (x - pivotX, y + h - pivotY),
        ]
        var path = Path()
        for (i, (cx, cy)) in corners.enumerated() {
            let rx = cx * ca - cy * sa + pivotX
            let ry = cx * sa + cy * ca + pivotY
            let pt = CGPoint(x: v.ox + rx * v.s, y: v.oy + (ry - v.y0 + dy) * v.s)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // SHARED: Draw face-portrait bust
    //   eyeScaleY  — 1.0 normal, 0.5 squint, 1.4 wide
    //   eyeDY      — vertical offset for eyes (scan up / startle)
    //   browDY     — vertical offset for brows (raised = negative)
    //   eyesClosed — replace eyes with thin lines (sleep)
    //   mouthOpen  — open oval instead of smile (alert)
    //   puff       — breathing width pulse (0..1)
    //   dy         — whole-face vertical translate (bounce/jump)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private func drawFace(_ ctx: GraphicsContext, v: V,
                          eyeScaleY: CGFloat = 1.0,
                          eyeDY: CGFloat = 0,
                          browDY: CGFloat = 0,
                          eyesClosed: Bool = false,
                          mouthOpen: Bool = false,
                          puff: CGFloat = 0,
                          dy: CGFloat = 0) {

        let pw = puff * 0.015  // ±width pulse magnitude

        // Hair — bun on top + wide side panels
        ctx.fill(Path(v.r(3.5, 0.2, 6,   2.3,        dy: dy)), with: .color(Self.hairC))
        ctx.fill(Path(v.r(1.5 - pw * 13, 1.5, 2.8 + pw * 13, 9, dy: dy)), with: .color(Self.hairC))
        ctx.fill(Path(v.r(8.7,           1.5, 2.8 + pw * 13, 9, dy: dy)), with: .color(Self.hairC))

        // Face base + cheek fills + chin taper
        ctx.fill(Path(v.r(3.5 - pw * 6,  1.8, 6 + pw * 12, 8.5, dy: dy)), with: .color(Self.skinC))
        ctx.fill(Path(v.r(2.5 - pw * 3,  3,   1.5 + pw * 3, 6,  dy: dy)), with: .color(Self.skinC))
        ctx.fill(Path(v.r(9.0,           3,   1.5 + pw * 3, 6,  dy: dy)), with: .color(Self.skinC))
        ctx.fill(Path(v.r(4.5,           9.5, 4,   1.5,         dy: dy)), with: .color(Self.skinC))

        // Eyebrows
        ctx.fill(Path(v.r(4.0,  3.2 + browDY, 2.2, 0.45, dy: dy)), with: .color(Self.browC))
        ctx.fill(Path(v.r(6.8,  3.2 + browDY, 2.2, 0.45, dy: dy)), with: .color(Self.browC))

        // Eyes
        if eyesClosed {
            // Thin closed-eye lines
            ctx.fill(Path(v.r(3.8,  4.5 + eyeDY, 2.6, 0.3, dy: dy)), with: .color(Self.eyeC))
            ctx.fill(Path(v.r(6.6,  4.5 + eyeDY, 2.6, 0.3, dy: dy)), with: .color(Self.eyeC))
        } else {
            // Upper lash bar
            ctx.fill(Path(v.r(3.8,  4.0 + eyeDY, 2.6, 0.4,             dy: dy)), with: .color(Self.eyeC))
            ctx.fill(Path(v.r(6.6,  4.0 + eyeDY, 2.6, 0.4,             dy: dy)), with: .color(Self.eyeC))
            // Eye body
            let eyeH = 1.4 * eyeScaleY
            ctx.fill(Path(v.r(3.8,  4.35 + eyeDY, 2.6, eyeH,           dy: dy)), with: .color(Self.eyeC))
            ctx.fill(Path(v.r(6.6,  4.35 + eyeDY, 2.6, eyeH,           dy: dy)), with: .color(Self.eyeC))
        }

        // Nose hint
        ctx.fill(Path(v.r(6.0,  6.8, 1.0, 0.7, dy: dy)), with: .color(Self.browC.opacity(0.5)))

        // Mouth
        if mouthOpen {
            // Small open oval — draw as tall rect with slight inset
            ctx.fill(Path(v.r(5.0,  8.0, 3.0, 1.4, dy: dy)), with: .color(Self.eyeC.opacity(0.85)))
        } else {
            // Smile bar
            ctx.fill(Path(v.r(4.5,  8.2, 4.0, 0.9, dy: dy)), with: .color(Self.lipC))
            // Teeth (only when eyes open)
            if !eyesClosed {
                ctx.fill(Path(v.r(5.0,  8.3, 3.0, 0.6, dy: dy)), with: .color(Self.teethC))
            }
        }

        // Neck
        ctx.fill(Path(v.r(5.8, 10.5, 1.4, 1.8, dy: dy)), with: .color(Self.skinC))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // SLEEP — face only, eyes closed, breathing, floating z's
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var sleepScene: some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 0.06)) { ctx in
                sleepCanvas(t: ctx.date.timeIntervalSinceReferenceDate * speed)
            }
            TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate * speed
                floatingZs(t: t)
            }
        }
    }

    private func sleepCanvas(t: Double) -> some View {
        let phase   = t.truncatingRemainder(dividingBy: 4.5) / 4.5
        let breathe: CGFloat = phase < 0.4 ? sin(phase / 0.4 * .pi) : 0

        return Canvas { c, sz in
            let v = V(sz, svgW: 13, svgH: 12, svgY0: 6)

            // Shadow pulses with breath
            let shadowScale: CGFloat = 1.0 + breathe * 0.03
            c.fill(Path(v.r(2, 11.8, 9 * shadowScale, 0.6)),
                   with: .color(.black.opacity(0.30 + breathe * 0.08)))

            drawFace(c, v: v, eyesClosed: true, puff: breathe)
        }
    }

    private func floatingZs(t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in floatingZ(t: t, index: i) }
        }
    }

    private func floatingZ(t: Double, index: Int) -> some View {
        let ci    = Double(index)
        let cycle = 2.8 + ci * 0.3
        let delay = ci * 0.9
        let phase = ((t - delay).truncatingRemainder(dividingBy: cycle)) / cycle
        let p     = max(0, phase)
        let fontSize   = max(6, size * CGFloat(0.18 + p * 0.10))
        let baseOpacity = 0.7 - ci * 0.1
        let opacity    = p < 0.8 ? baseOpacity : (1.0 - p) * 3.5 * baseOpacity
        let xOff = size * CGFloat(0.08 + ci * 0.06 + sin(p * .pi * 2) * 0.03)
        let yOff = -size * CGFloat(0.15 + p * 0.38)
        return Text("z")
            .font(.system(size: fontSize, weight: .black, design: .monospaced))
            .foregroundStyle(.white.opacity(opacity))
            .offset(x: xOff, y: yOff)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // WORK — squinting face + typing arms + keyboard
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var workScene: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * speed
            workCanvas(t: t)
        }
    }

    private func workCanvas(t: Double) -> some View {
        let bounce  = sin(t * Self.freqBounce) * 1.2
        let breathe = sin(t * Self.freqBreathe)

        let armLRaw = sin(t * Self.freqArmL)
        let armL    = armLRaw * 22.5 - 32.5   // -55 to -10
        let armRRaw = sin(t * Self.freqArmR)
        let armR    = armRRaw * 22.5 + 32.5   // 10 to 55

        let leftHit     = armLRaw > 0.3
        let rightHit    = armRRaw > 0.3
        let leftKeyCol  = Int(t / 0.15) % 3
        let rightKeyCol = 3 + Int(t / 0.12) % 3

        let scanPhase   = t.truncatingRemainder(dividingBy: 10.0)
        let eyeScale: CGFloat = (scanPhase > 5.7 && scanPhase < 6.9) ? 1.0 : 0.5
        let eyeDY: CGFloat    = eyeScale < 0.8 ? 1.0 : -0.5
        let blinkPhase  = t.truncatingRemainder(dividingBy: 3.5)
        let finalEyeScale = (blinkPhase > 1.4 && blinkPhase < 1.55) ? 0.1 : eyeScale

        return Canvas { c, sz in
            let v  = V(sz, svgW: 14, svgH: 14, svgY0: 5)
            let dy = bounce

            // Shadow
            let shadowW: CGFloat = 9 - abs(dy) * 0.3
            c.fill(Path(v.r(2.5 + (9 - shadowW) / 2, 13.5, shadowW, 0.7)),
                   with: .color(.black.opacity(max(0.1, 0.4 - abs(dy) * 0.03))))

            // Face (bust)
            drawFace(c, v: v,
                     eyeScaleY: finalEyeScale,
                     eyeDY: eyeDY,
                     puff: CGFloat(breathe),
                     dy: dy)

            // Arms — pivot at shoulders (bottom of face canvas)
            c.fill(armPath(v, x: 0.5, y: 10, w: 2, h: 2, pivotX: 2, pivotY: 12,
                           angle: armL, dy: dy), with: .color(Self.skinC))
            c.fill(armPath(v, x: 11.5, y: 10, w: 2, h: 2, pivotX: 12, pivotY: 12,
                           angle: armR, dy: dy), with: .color(Self.skinC))

            // Keyboard (y 12–14 range)
            c.fill(Path(v.r(-0.5, 12.0, 15, 3.0)), with: .color(Self.kbBase))
            for row in 0..<3 {
                let ky = 12.3 + CGFloat(row) * 0.9
                for col in 0..<6 {
                    let kx = 0.3 + CGFloat(col) * 2.3
                    let w: CGFloat = (col == 2 && row == 1) ? 4.0 : 1.8
                    c.fill(Path(v.r(kx, ky, w, 0.6)), with: .color(Self.kbKey))
                }
            }
            if leftHit {
                let row = leftKeyCol % 3
                let kx  = 0.3 + CGFloat(leftKeyCol) * 2.3
                let ky  = 12.3 + CGFloat(row) * 0.9
                c.fill(Path(v.r(kx, ky, 1.8, 0.6)), with: .color(Self.kbHi.opacity(0.9)))
            }
            if rightHit {
                let row = (rightKeyCol - 3) % 3
                let kx  = 0.3 + CGFloat(rightKeyCol) * 2.3
                let ky  = 12.3 + CGFloat(row) * 0.9
                c.fill(Path(v.r(kx, ky, 1.8, 0.6)), with: .color(Self.kbHi.opacity(0.9)))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // ALERT — startle: wide eyes, jump, waving arms, ! mark
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var alertScene: some View {
        ZStack {
            Circle()
                .fill(Self.alertC.opacity(alive ? 0.12 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: alive)

            TimelineView(.periodic(from: .now, by: 0.03)) { ctx in
                alertCanvas(t: ctx.date.timeIntervalSinceReferenceDate * speed)
            }
        }
    }

    private func lerp(_ keyframes: [(CGFloat, CGFloat)], at pct: CGFloat) -> CGFloat {
        guard let first = keyframes.first else { return 0 }
        if pct <= first.0 { return first.1 }
        for i in 1..<keyframes.count {
            if pct <= keyframes[i].0 {
                let t = (pct - keyframes[i-1].0) / (keyframes[i].0 - keyframes[i-1].0)
                return keyframes[i-1].1 + (keyframes[i].1 - keyframes[i-1].1) * t
            }
        }
        return keyframes.last?.1 ?? 0
    }

    private func alertCanvas(t: Double) -> some View {
        let cycle = t.truncatingRemainder(dividingBy: 3.5)
        let pct   = cycle / 3.5

        let jumpY = lerp([
            (0, 0), (0.03, 0), (0.10, -1), (0.15, 1.5),
            (0.175, -10), (0.20, -10), (0.25, 1.5),
            (0.275, -8),  (0.30, -8),  (0.35, 1.2),
            (0.375, -5),  (0.40, -5),  (0.45, 1.0),
            (0.475, -3),  (0.50, -3),  (0.55, 0.5),
            (0.62, 0),    (1.0, 0),
        ], at: pct)

        let armL = lerp([
            (0, 0),    (0.03, 0),   (0.10, 25),
            (0.15, 30),(0.20, 155), (0.25, 115),
            (0.30, 140),(0.35, 100),(0.40, 115),
            (0.45, 80),(0.50, 80),  (0.55, 40),
            (0.62, 0), (1.0, 0),
        ], at: pct)
        let armR = -lerp([
            (0, 0),    (0.03, 0),   (0.10, 30),
            (0.15, 30),(0.20, 155), (0.25, 115),
            (0.30, 140),(0.35, 100),(0.40, 115),
            (0.45, 80),(0.50, 80),  (0.55, 40),
            (0.62, 0), (1.0, 0),
        ], at: pct)

        let isStartle = pct > 0.03 && pct < 0.15
        let eyeScale: CGFloat = isStartle ? 1.4 : 1.0
        let eyeDY: CGFloat    = isStartle ? -0.5 : 0
        let browDY: CGFloat   = isStartle ? -0.6 : 0

        let bangOpacity = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = V(sz, svgW: 13, svgH: 15, svgY0: 4)

            // Shadow
            let shadowW: CGFloat = 9 * (1.0 - abs(min(0, jumpY)) * 0.04)
            let shadowOp = max(0.08, 0.5 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(2 + (9 - shadowW) / 2, 13.0, shadowW, 0.7)),
                   with: .color(.black.opacity(shadowOp)))

            // Face
            drawFace(c, v: v,
                     eyeScaleY: eyeScale,
                     eyeDY: eyeDY,
                     browDY: browDY,
                     mouthOpen: isStartle,
                     dy: jumpY)

            // Arms — pivot at shoulders
            c.fill(armPath(v, x: 0.5, y: 9, w: 2, h: 2, pivotX: 2, pivotY: 11,
                           angle: armL, dy: jumpY), with: .color(Self.skinC))
            c.fill(armPath(v, x: 10.5, y: 9, w: 2, h: 2, pivotX: 11, pivotY: 11,
                           angle: armR, dy: jumpY), with: .color(Self.skinC))

            // ! mark
            if bangOpacity > 0.01 {
                let bw: CGFloat = 2 * bangScale
                let bx: CGFloat = 10.5
                let by: CGFloat = 4.5 + jumpY * 0.15
                c.fill(Path(v.r(bx, by,                    bw, 3.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOpacity)))
                c.fill(Path(v.r(bx, by + 4.0 * bangScale,  bw, 1.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOpacity)))
            }
        }
    }
}
