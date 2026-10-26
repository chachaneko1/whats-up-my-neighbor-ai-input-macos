import SwiftUI

// Native port of the accepted sakura v4 geometry and deterministic motion.
struct SakuraView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let start = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 8 : timeline.date.timeIntervalSince(start)
                for i in 0..<28 {
                    let n = Double(i)
                    let r1 = sin(n * 7.31 + 1.1) * 0.5 + 0.5
                    let r2 = sin(n * 3.73 + 2.3) * 0.5 + 0.5
                    let r3 = sin(n * 5.17 + 0.7) * 0.5 + 0.5
                    let r4 = sin(n * 11.2 + 3.1) * 0.5 + 0.5
                    let speed = (32 + r2 * 30) * 0.65
                    let fullH = size.height + 60
                    let raw = (t * speed + n / 28 * fullH).truncatingRemainder(dividingBy: fullH)
                    let lt = raw / speed
                    let x = (0.08 + r1 * 0.94) * size.width - (5 + r4 * 9) * 0.4 * lt + (10 + r3 * 20) * sin(lt * (0.26 + r1 * 0.18) + n * 1.57)
                    let w = (7.5 + r3 * 3) * 0.88
                    let h = (8.5 + r1 * 2) * 0.88
                    var c = context
                    c.translateBy(x: x, y: raw - 30)
                    c.rotate(by: .degrees(r4 * 360 + lt * (38 + r2 * 60)))
                    c.opacity = 0.90 + r3 * 0.08
                    var p = Path()
                    p.move(to: CGPoint(x: -w * 0.12, y: h * 0.88))
                    p.addCurve(to: CGPoint(x: -w * 0.52, y: -h * 0.68), control1: CGPoint(x: -w * 0.90, y: h * 0.48), control2: CGPoint(x: -w * 1.02, y: -h * 0.22))
                    p.addQuadCurve(to: CGPoint(x: w * 0.08, y: -h * 0.94), control: CGPoint(x: -w * 0.25, y: -h * 0.94))
                    p.addLine(to: CGPoint(x: w * 0.12, y: -h * 0.58))
                    p.addLine(to: CGPoint(x: w * 0.43, y: -h * 0.82))
                    p.addCurve(to: CGPoint(x: -w * 0.12, y: h * 0.88), control1: CGPoint(x: w * 0.98, y: -h * 0.46), control2: CGPoint(x: w * 0.84, y: h * 0.40))
                    p.closeSubpath()
                    c.fill(p, with: .linearGradient(Gradient(colors: [Color(hex: 0xFCF4F5), Color(hex: 0xF8E7EB), Color(hex: 0xF0D9DF)]), startPoint: CGPoint(x: -w * 0.7, y: -h * 0.8), endPoint: CGPoint(x: w * 0.6, y: h * 0.8)))
                    c.stroke(p, with: .color(Color(hex: 0xB9A0A8).opacity(0.5)), lineWidth: 0.6)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
