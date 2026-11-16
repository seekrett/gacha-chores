import SwiftUI

// MARK: - Shapes

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct ArcShape: Shape {
    var bulgeDown = true
    func path(in r: CGRect) -> Path {
        var p = Path()
        if bulgeDown {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: 2 * r.maxY - r.minY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: 2 * r.minY - r.maxY))
        }
        return p
    }
}

struct RaysShape: Shape {
    var count = 14
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = max(rect.width, rect.height)
        let half = Double.pi / Double(count) * 0.45
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * Double.pi
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + r * cos(a - half), y: c.y + r * sin(a - half)))
            p.addLine(to: CGPoint(x: c.x + r * cos(a + half), y: c.y + r * sin(a + half)))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Figure

/// Draws a collectible vinyl-toy style figure from its `FigureLook`.
struct FigureView: View {
    let figure: FigureDef
    var size: CGFloat = 100
    var silhouette = false
    var shiny = false

    private var look: FigureLook { figure.look }
    private let ink = Palette.ink

    var body: some View {
        Group {
            if silhouette {
                ZStack {
                    core.colorMultiply(.black).opacity(0.14)
                    Text("?")
                        .font(.system(size: size * 0.3, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .offset(y: size * 0.08)
                }
            } else if shiny || look.holo {
                core
                    .overlay { HoloSheen().mask(core) }
                    .overlay { SparkleCluster(size: size, color: look.holo ? Palette.gold : .white) }
            } else {
                core
            }
        }
        .frame(width: size, height: size)
    }

    private var bodyFill: AnyShapeStyle {
        if look.holo {
            return AnyShapeStyle(AngularGradient(colors: [Color(hex: 0xFFB3D9), Color(hex: 0xFFF0A8), Color(hex: 0xA8FFE0),
                                                          Color(hex: 0xA8D8FF), Color(hex: 0xD9B3FF), Color(hex: 0xFFB3D9)],
                                                 center: .center))
        }
        return AnyShapeStyle(LinearGradient(colors: [look.body.adjusted(brightness: 0.06), look.body.adjusted(brightness: -0.06)],
                                            startPoint: .top, endPoint: .bottom))
    }

    private var bodyShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: size * 0.29, bottomLeadingRadius: size * 0.2,
                               bottomTrailingRadius: size * 0.2, topTrailingRadius: size * 0.29,
                               style: .continuous)
    }

    private var core: some View {
        let s = size
        return ZStack {
            Ellipse().fill(.black.opacity(0.13))
                .frame(width: s * 0.5, height: s * 0.07)
                .offset(y: s * 0.44)

            ears(s)

            // feet
            HStack(spacing: s * 0.12) {
                Capsule().fill(look.body.adjusted(brightness: -0.14)).frame(width: s * 0.16, height: s * 0.09)
                Capsule().fill(look.body.adjusted(brightness: -0.14)).frame(width: s * 0.16, height: s * 0.09)
            }
            .offset(y: s * 0.4)

            // arms
            Capsule().fill(bodyFill).frame(width: s * 0.1, height: s * 0.2)
                .rotationEffect(.degrees(25)).offset(x: -s * 0.31, y: s * 0.15)
            Capsule().fill(bodyFill).frame(width: s * 0.1, height: s * 0.2)
                .rotationEffect(.degrees(-25)).offset(x: s * 0.31, y: s * 0.15)

            // body
            ZStack {
                bodyShape.fill(bodyFill)
                patternView(s).clipShape(bodyShape)
                Ellipse().fill(look.belly)
                    .frame(width: s * 0.36, height: s * 0.24)
                    .offset(y: s * 0.13)
                Ellipse().fill(.white.opacity(0.5))
                    .frame(width: s * 0.13, height: s * 0.07)
                    .rotationEffect(.degrees(-35))
                    .offset(x: -s * 0.17, y: -s * 0.2)
                face(s).offset(y: -s * 0.06)
            }
            .frame(width: s * 0.62, height: s * 0.6)
            .offset(y: s * 0.1)

            if let hat = look.hat {
                Image(systemName: hat)
                    .font(.system(size: s * 0.19, weight: .bold))
                    .foregroundStyle(look.accent.gradient)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .offset(y: -s * 0.27)
            }

            if let held = look.held {
                ZStack {
                    Circle().fill(.white)
                    Image(systemName: held)
                        .font(.system(size: s * 0.11, weight: .bold))
                        .foregroundStyle(look.accent.gradient)
                }
                .frame(width: s * 0.2, height: s * 0.2)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .offset(x: s * 0.31, y: s * 0.24)
            }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private func ears(_ s: CGFloat) -> some View {
        let sides: [CGFloat] = [-1, 1]
        switch look.ears {
        case .bunny:
            ForEach(sides, id: \.self) { side in
                ZStack {
                    Capsule().fill(bodyFill)
                    Capsule().fill(look.accent.opacity(0.4))
                        .frame(width: s * 0.055, height: s * 0.2)
                        .offset(y: s * 0.02)
                }
                .frame(width: s * 0.13, height: s * 0.34)
                .rotationEffect(.degrees(12 * side))
                .offset(x: s * 0.13 * side, y: -s * 0.3)
            }
        case .cat:
            ForEach(sides, id: \.self) { side in
                ZStack {
                    Triangle().fill(bodyFill)
                    Triangle().fill(look.accent.opacity(0.4))
                        .frame(width: s * 0.1, height: s * 0.1)
                        .offset(y: s * 0.03)
                }
                .frame(width: s * 0.2, height: s * 0.2)
                .rotationEffect(.degrees(16 * side))
                .offset(x: s * 0.18 * side, y: -s * 0.22)
            }
        case .bear:
            ForEach(sides, id: \.self) { side in
                ZStack {
                    Circle().fill(bodyFill)
                    Circle().fill(look.accent.opacity(0.35)).frame(width: s * 0.09, height: s * 0.09)
                }
                .frame(width: s * 0.18, height: s * 0.18)
                .offset(x: s * 0.21 * side, y: -s * 0.17)
            }
        case .floppy:
            ForEach(sides, id: \.self) { side in
                Capsule().fill(look.body.adjusted(brightness: -0.08))
                    .frame(width: s * 0.14, height: s * 0.3)
                    .rotationEffect(.degrees(-28 * side))
                    .offset(x: s * 0.3 * side, y: -s * 0.04)
            }
        case .antenna:
            ForEach(sides, id: \.self) { side in
                ZStack {
                    Capsule().fill(ink.opacity(0.8))
                        .frame(width: s * 0.022, height: s * 0.14)
                        .rotationEffect(.degrees(15 * side))
                        .offset(x: s * 0.09 * side, y: -s * 0.27)
                    Circle().fill(look.accent.gradient)
                        .frame(width: s * 0.07, height: s * 0.07)
                        .offset(x: s * 0.11 * side, y: -s * 0.35)
                }
            }
        case .horns:
            ForEach(sides, id: \.self) { side in
                Triangle().fill(look.accent.gradient)
                    .frame(width: s * 0.1, height: s * 0.15)
                    .rotationEffect(.degrees(15 * side))
                    .offset(x: s * 0.14 * side, y: -s * 0.24)
            }
        case .sprout:
            ZStack {
                Capsule().fill(Color(hex: 0x4FB54A))
                    .frame(width: s * 0.025, height: s * 0.1)
                    .offset(y: -s * 0.24)
                Image(systemName: "leaf.fill")
                    .font(.system(size: s * 0.13))
                    .foregroundStyle(Color(hex: 0x5CC74F))
                    .offset(x: s * 0.06, y: -s * 0.31)
                Image(systemName: "leaf.fill")
                    .font(.system(size: s * 0.11))
                    .foregroundStyle(Color(hex: 0x4FB54A))
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: -s * 0.05, y: -s * 0.3)
            }
        case .none:
            EmptyView()
        }
    }

    private func face(_ s: CGFloat) -> some View {
        ZStack {
            HStack(spacing: s * 0.12) {
                eye(s, isLeft: true)
                eye(s, isLeft: false)
            }
            HStack(spacing: s * 0.25) {
                Ellipse().fill(Color(hex: 0xFF7FA8).opacity(0.45)).frame(width: s * 0.08, height: s * 0.045)
                Ellipse().fill(Color(hex: 0xFF7FA8).opacity(0.45)).frame(width: s * 0.08, height: s * 0.045)
            }
            .offset(y: s * 0.06)
            mouth(s).offset(y: s * 0.07)
        }
    }

    private func dotEye(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(ink).frame(width: s * 0.075, height: s * 0.075)
            Circle().fill(.white).frame(width: s * 0.025, height: s * 0.025)
                .offset(x: -s * 0.013, y: -s * 0.015)
        }
        .frame(width: s * 0.09, height: s * 0.09)
    }

    private func arcEye(_ s: CGFloat, down: Bool) -> some View {
        ArcShape(bulgeDown: down)
            .stroke(ink, style: StrokeStyle(lineWidth: s * 0.018, lineCap: .round))
            .frame(width: s * 0.07, height: s * 0.03)
            .frame(width: s * 0.09, height: s * 0.09)
    }

    @ViewBuilder
    private func eye(_ s: CGFloat, isLeft: Bool) -> some View {
        switch look.eyes {
        case .dot:
            dotEye(s)
        case .sparkle:
            ZStack {
                Ellipse().fill(ink).frame(width: s * 0.085, height: s * 0.105)
                Circle().fill(.white).frame(width: s * 0.032, height: s * 0.032)
                    .offset(x: -s * 0.015, y: -s * 0.022)
                Circle().fill(.white).frame(width: s * 0.015, height: s * 0.015)
                    .offset(x: s * 0.016, y: s * 0.02)
            }
            .frame(width: s * 0.09, height: s * 0.11)
        case .sleepy:
            arcEye(s, down: true)
        case .happy:
            arcEye(s, down: false)
        case .wink:
            if isLeft { dotEye(s) } else { arcEye(s, down: false) }
        case .star:
            Image(systemName: "star.fill")
                .font(.system(size: s * 0.085, weight: .black))
                .foregroundStyle(ink)
                .frame(width: s * 0.09, height: s * 0.09)
        }
    }

    @ViewBuilder
    private func mouth(_ s: CGFloat) -> some View {
        let stroke = StrokeStyle(lineWidth: s * 0.016, lineCap: .round)
        switch look.mouth {
        case .smile:
            ArcShape(bulgeDown: true).stroke(ink, style: stroke)
                .frame(width: s * 0.07, height: s * 0.028)
        case .cat:
            HStack(spacing: 0) {
                ArcShape(bulgeDown: true).stroke(ink, style: stroke).frame(width: s * 0.038, height: s * 0.022)
                ArcShape(bulgeDown: true).stroke(ink, style: stroke).frame(width: s * 0.038, height: s * 0.022)
            }
        case .open:
            ZStack(alignment: .bottom) {
                Ellipse().fill(ink)
                Ellipse().fill(Color(hex: 0xFF7FA8)).frame(width: s * 0.04, height: s * 0.028)
            }
            .frame(width: s * 0.065, height: s * 0.055)
            .clipShape(Ellipse())
        case .fang:
            ZStack(alignment: .top) {
                ArcShape(bulgeDown: true).stroke(ink, style: stroke)
                    .frame(width: s * 0.08, height: s * 0.028)
                Triangle().fill(.white)
                    .frame(width: s * 0.022, height: s * 0.024)
                    .rotationEffect(.degrees(180))
                    .offset(x: s * 0.016, y: s * 0.016)
            }
        case .tiny:
            Ellipse().fill(ink).frame(width: s * 0.03, height: s * 0.022)
        }
    }

    private static let spots: [(x: CGFloat, y: CGFloat, d: CGFloat)] = [
        (-0.2, -0.16, 0.08), (0.18, -0.2, 0.06), (0.22, 0.04, 0.07), (-0.24, 0.1, 0.05), (0.04, -0.27, 0.05), (-0.05, 0.25, 0.05),
    ]

    @ViewBuilder
    private func patternView(_ s: CGFloat) -> some View {
        switch look.pattern {
        case .none:
            Color.clear
        case .spots:
            ZStack {
                ForEach(0..<Self.spots.count, id: \.self) { i in
                    let spot = Self.spots[i]
                    Circle().fill(look.accent.opacity(0.35))
                        .frame(width: s * spot.d, height: s * spot.d)
                        .offset(x: s * spot.x, y: s * spot.y)
                }
            }
        case .stripes:
            VStack(spacing: s * 0.06) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle().fill(look.accent.opacity(0.2)).frame(height: s * 0.04)
                }
            }
        case .hearts:
            ZStack {
                ForEach(0..<Self.spots.count, id: \.self) { i in
                    let spot = Self.spots[i]
                    Image(systemName: "heart.fill")
                        .font(.system(size: s * spot.d))
                        .foregroundStyle(look.accent.opacity(0.4))
                        .offset(x: s * spot.x, y: s * spot.y)
                }
            }
        }
    }
}

// MARK: - Effects

struct HoloSheen: View {
    @State private var move = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: Palette.rainbow, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.25)
                    .blendMode(.overlay)
                LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.4)
                    .rotationEffect(.degrees(20))
                    .offset(x: move ? geo.size.width : -geo.size.width)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.4)) { move = true }
        }
    }
}

struct SparkleCluster: View {
    let size: CGFloat
    var color: Color = .white
    var body: some View {
        ZStack {
            sparkle(0.14, x: -0.36, y: -0.3)
            sparkle(0.1, x: 0.38, y: -0.12)
            sparkle(0.08, x: -0.3, y: 0.3)
        }
        .allowsHitTesting(false)
    }

    private func sparkle(_ d: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * d, weight: .bold))
            .foregroundStyle(color)
            .shadow(color: Palette.gold.opacity(0.8), radius: 3)
            .symbolEffect(.pulse, options: .repeating)
            .offset(x: size * x, y: size * y)
    }
}

// MARK: - Blind box

struct BlindBoxView: View {
    let series: Series
    var size: CGFloat = 120
    var lidLift: CGFloat = 0
    var glow: Color? = nil

    var body: some View {
        let s = size
        ZStack {
            if let glow {
                RoundedRectangle(cornerRadius: s * 0.15)
                    .fill(glow)
                    .frame(width: s * 0.95, height: s * 0.85)
                    .blur(radius: s * 0.12)
                    .offset(y: s * 0.08)
            }

            // box body
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.07, style: .continuous)
                    .fill(LinearGradient(colors: series.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                // polka dots
                ForEach(0..<6, id: \.self) { i in
                    Circle().fill(.white.opacity(0.14))
                        .frame(width: s * 0.09, height: s * 0.09)
                        .offset(x: s * (i.isMultiple(of: 2) ? -0.26 : 0.26), y: s * (CGFloat(i / 2) * 0.18 - 0.18))
                }
                Rectangle().fill(.white.opacity(0.85)).frame(width: s * 0.09)
                ZStack {
                    Circle().fill(series.colors.last ?? Palette.berry)
                    Circle().stroke(.white, lineWidth: s * 0.02)
                    VStack(spacing: -s * 0.02) {
                        Image(systemName: series.symbol).font(.system(size: s * 0.09, weight: .bold))
                        Text("?").font(.system(size: s * 0.15, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: s * 0.34, height: s * 0.34)
                // gloss
                RoundedRectangle(cornerRadius: s * 0.05)
                    .fill(.white.opacity(0.22))
                    .frame(width: s * 0.06, height: s * 0.4)
                    .offset(x: -s * 0.3)
            }
            .frame(width: s * 0.78, height: s * 0.62)
            .clipShape(RoundedRectangle(cornerRadius: s * 0.07, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: s * 0.04, y: s * 0.03)
            .offset(y: s * 0.14)

            // lid
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                    .fill((series.colors.first ?? Palette.pink).adjusted(brightness: -0.08).gradient)
                Rectangle().fill(.white.opacity(0.9)).frame(width: s * 0.09)
                Image(systemName: "heart.fill")
                    .font(.system(size: s * 0.09))
                    .foregroundStyle(.white)
                    .offset(y: -s * 0.09)
            }
            .frame(width: s * 0.86, height: s * 0.16)
            .offset(y: -s * 0.17)
            .rotationEffect(.degrees(Double(lidLift) * -32), anchor: .leading)
            .offset(x: lidLift * s * 0.4, y: -lidLift * s * 0.8)
            .opacity(Double(1 - lidLift * 0.7))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
        }
        .frame(width: s, height: s)
    }
}

// MARK: - Confetti

struct ConfettiView: View {
    var colors: [Color] = Palette.rainbow + [Palette.gold]
    var count = 90

    private struct Particle {
        let vx: Double, vy: Double, spin: Double, size: Double, colorIndex: Int, isCircle: Bool
    }

    @State private var start = Date()
    @State private var particles: [Particle] = []

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < 4 else { return }
                for p in particles {
                    let x = size.width / 2 + p.vx * t * size.width
                    let y = size.height * 0.42 + (p.vy * t + 0.55 * t * t) * size.height
                    let fade = max(0, 1 - t / 4)
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * t))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.isCircle ? p.size : p.size / 2)
                    let path = p.isCircle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    c.fill(path, with: .color(colors[p.colorIndex % colors.count].opacity(fade)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            start = Date()
            particles = (0..<count).map { _ in
                Particle(vx: .random(in: -0.45...0.45), vy: .random(in: -0.75 ... -0.2),
                         spin: .random(in: -8...8), size: .random(in: 6...12),
                         colorIndex: .random(in: 0..<100), isCircle: Bool.random())
            }
        }
    }
}
