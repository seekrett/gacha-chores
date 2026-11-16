import SwiftUI

/// Full-screen unboxing ritual: pick a box, shake it, tear it open, meet your new friend.
struct UnboxingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    let session: PullSession

    @State private var picked: Bool
    @State private var index = 0
    @State private var showSummary = false

    init(session: PullSession) {
        self.session = session
        _picked = State(initialValue: !session.pickFromShelf)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B1235), (session.series.colors.last ?? .purple).adjusted(brightness: -0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if !picked {
                ShelfPicker(series: session.series) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { picked = true }
                }
                .transition(.opacity)
            } else if showSummary {
                SummaryView(results: session.results) { dismiss() }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                SingleUnboxView(result: session.results[index],
                                series: session.series,
                                position: session.results.count > 1 ? "\(index + 1) of \(session.results.count)" : nil,
                                isLast: index == session.results.count - 1) {
                    advance()
                }
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }

            VStack {
                HStack {
                    Spacer()
                    if picked && !showSummary && session.results.count > 1 {
                        Button("Skip") { withAnimation { showSummary = true } }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if index < session.results.count - 1 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { index += 1 }
        } else if session.results.count > 1 {
            withAnimation { showSummary = true }
        } else {
            dismiss()
        }
    }
}

private struct ShelfPicker: View {
    let series: Series
    var onPick: () -> Void
    @State private var chosen: Int?
    @State private var wobble = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Pick your box").font(.largeTitle.bold())
                Text("Trust your gut. One of these is calling you.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 18) {
                ForEach(0..<9, id: \.self) { i in
                    BlindBoxView(series: series, size: 96)
                        .rotationEffect(.degrees(wobble && i % 2 == 0 ? 2 : (wobble ? -2 : 0)))
                        .scaleEffect(chosen == i ? 1.25 : 1)
                        .opacity(chosen == nil || chosen == i ? 1 : 0.25)
                        .onTapGesture {
                            guard chosen == nil else { return }
                            Haptics.impact(.rigid)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { chosen = i }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onPick() }
                        }
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { wobble = true }
        }
    }
}

private struct SingleUnboxView: View {
    let result: PullResult
    let series: Series
    let position: String?
    let isLast: Bool
    var onNext: () -> Void

    @State private var taps = 0
    @State private var opened = false
    @State private var revealed = false
    @State private var spin = 0.0
    @State private var burst = false
    @State private var float = false

    private var rarity: Rarity { result.figure.rarity }

    private var prompt: String {
        switch taps {
        case 0: "Tap the box to shake it"
        case 1: "Something's rattling inside…"
        default: rarity >= .epic ? "Whoa, it's glowing!! One more tap!" : "One more tap!"
        }
    }

    var body: some View {
        ZStack {
            if revealed && rarity >= .epic {
                ConfettiView(colors: rarity == .secret ? Palette.rainbow + [Palette.gold, Palette.gold] : [rarity.color, .white, Palette.pink, Palette.gold])
            }

            VStack(spacing: 18) {
                if let position {
                    Text(position).font(.caption.bold()).foregroundStyle(.white.opacity(0.6))
                }
                Text(revealed ? " " : prompt)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: taps)

                ZStack {
                    if revealed {
                        RaysShape(count: 16)
                            .fill(RadialGradient(colors: [rarity.color.opacity(0.75), .clear], center: .center, startRadius: 10, endRadius: 220))
                            .frame(width: 440, height: 440)
                            .rotationEffect(.degrees(spin))
                            .transition(.opacity)
                    }
                    Circle()
                        .fill(RadialGradient(colors: [.white, rarity.color.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 160))
                        .frame(width: 320, height: 320)
                        .scaleEffect(burst ? 1.6 : 0.1)
                        .opacity(burst ? (revealed ? 0.35 : 1) : 0)

                    if revealed {
                        FigureView(figure: result.figure, size: 240)
                            .offset(y: float ? -8 : 8)
                            .transition(.scale(scale: 0.2).combined(with: .offset(y: 120)).combined(with: .opacity))
                    } else {
                        BlindBoxView(series: series, size: 230, lidLift: opened ? 1 : 0, glow: taps >= 2 ? rarity.color : nil)
                            .scaleEffect(1 + CGFloat(taps) * 0.03)
                            .keyframeAnimator(initialValue: 0.0, trigger: taps) { content, angle in
                                content.rotationEffect(.degrees(angle), anchor: .bottom)
                            } keyframes: { _ in
                                let amp = 4.0 + Double(taps) * 4.0
                                KeyframeTrack {
                                    LinearKeyframe(-amp, duration: 0.06)
                                    LinearKeyframe(amp, duration: 0.08)
                                    LinearKeyframe(-amp * 0.7, duration: 0.08)
                                    LinearKeyframe(amp * 0.5, duration: 0.08)
                                    SpringKeyframe(0, duration: 0.25)
                                }
                            }
                            .onTapGesture { tap() }
                    }
                }
                .frame(width: 300, height: 320)

                if revealed {
                    revealCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(i < taps ? Color.white : Color.white.opacity(0.25)).frame(width: 10, height: 10)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var revealCard: some View {
        VStack(spacing: 10) {
            if rarity == .secret {
                Text("✨ SECRET FIGURE ✨")
                    .font(.headline.weight(.black))
                    .foregroundStyle(LinearGradient(colors: Palette.rainbow, startPoint: .leading, endPoint: .trailing))
            }
            HStack(spacing: 8) {
                RarityBadge(rarity: rarity)
                if result.isNew {
                    Text("NEW!")
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.berry))
                        .foregroundStyle(.white)
                }
                if result.wasPity {
                    Text("Guaranteed")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.2)))
                        .foregroundStyle(.white)
                }
            }
            Text(result.figure.name).font(.largeTitle.bold()).foregroundStyle(.white)
            Text(result.figure.flavor)
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if !result.isNew {
                Label("Duplicate → +\(result.glitter) Glitter", systemImage: "diamond.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Palette.lavender)
            }
            Button(isLast ? "Done" : "Next box") { onNext() }
                .buttonStyle(BubblyButtonStyle(color: rarity.color))
                .padding(.top, 6)
        }
    }

    private func tap() {
        guard !opened else { return }
        taps += 1
        switch taps {
        case 1: Haptics.impact(.light)
        case 2: Haptics.impact(.medium)
        default: Haptics.impact(.heavy)
        }
        guard taps >= 3 else { return }
        withAnimation(.easeIn(duration: 0.35)) { opened = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.2)) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { revealed = true }
            if rarity >= .epic { Haptics.success() } else { Haptics.impact(.soft) }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = 360 }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { float = true }
        }
    }
}

private struct SummaryView: View {
    let results: [PullResult]
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Your haul").font(.largeTitle.bold()).foregroundStyle(.white)
            let newCount = results.filter(\.isNew).count
            Text("\(newCount) new · \(results.count - newCount) duplicate\(results.count - newCount == 1 ? "" : "s")")
                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                ForEach(results.sorted { $0.figure.rarity > $1.figure.rarity }) { r in
                    VStack(spacing: 4) {
                        FigureView(figure: r.figure, size: 78)
                            .background(Circle().fill(r.figure.rarity.color.opacity(0.25)).blur(radius: 10))
                        Text(r.figure.name).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 4) {
                            Circle().fill(r.figure.rarity.color).frame(width: 6, height: 6)
                            Text(r.isNew ? "NEW" : "+\(r.glitter) ◆")
                                .font(.caption2.bold())
                                .foregroundStyle(r.isNew ? Palette.pink : Palette.lavender)
                        }
                    }
                }
            }
            Button("Add to collection", action: onDone)
                .buttonStyle(BubblyButtonStyle())
                .padding(.top)
        }
        .padding()
    }
}
