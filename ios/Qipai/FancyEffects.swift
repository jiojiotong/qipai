import SwiftUI

// MARK: - 腾讯式牌桌背景：木质边框 + 径向绿毡
struct FancyTableBackground: View {
    var body: some View {
        ZStack {
            // 深色底
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .ignoresSafeArea()
            // 木质边框
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.2, blue: 0.1),
                            Color(red: 0.25, green: 0.13, blue: 0.06),
                            Color(red: 0.35, green: 0.2, blue: 0.1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .padding(8)
            // 绿毡（径向渐变，中间亮）
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.15, green: 0.45, blue: 0.25),
                            Color(red: 0.08, green: 0.3, blue: 0.16),
                            Color(red: 0.05, green: 0.2, blue: 0.1),
                        ],
                        center: .center,
                        startRadius: 20, endRadius: 400
                    )
                )
                .padding(16)
            // 暗角
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.35)],
                        center: .center,
                        startRadius: 150, endRadius: 400
                    )
                )
                .padding(16)
        }
    }
}

// MARK: - 发牌动画：从中央飞到手牌区
struct DealingCardsView: View {
    let count: Int
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<min(count, 10), id: \.self) { i in
                CardBackView(small: true)
                    .offset(
                        x: CGFloat(i - 5) * 12 * progress,
                        y: (1 - progress) * -200 + CGFloat(i % 3) * 4 * progress
                    )
                    .opacity(progress > 0.1 ? 1 : 0)
                    .rotationEffect(.degrees(Double(i - 5) * 3 * progress))
            }
        }
        .onAppear {
            SoundManager.shared.play("deal")
            withAnimation(.easeOut(duration: 0.6)) { progress = 1 }
        }
    }
}

// MARK: - 金币飞行动画
struct CoinFlyView: View {
    let fromBottom: Bool  // true=从下往上飞（赢），false=从上往下（输）
    @State private var progress: Double = 0
    let onDone: () -> Void

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Text("🪙")
                    .font(.system(size: 24))
                    .offset(
                        x: CGFloat(i - 6) * 18 + CGFloat.random(in: -10...10),
                        y: fromBottom
                            ? (1 - progress) * 300 - progress * 100
                            : progress * 300 - (1 - progress) * 100
                    )
                    .opacity(1 - progress * 0.5)
                    .scaleEffect(1 - progress * 0.3)
            }
        }
        .onAppear {
            SoundManager.shared.play("win")
            withAnimation(.easeInOut(duration: 1.0)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { onDone() }
        }
    }
}

// MARK: - 得分飘字
struct ScorePopupView: View {
    let text: String
    let isPositive: Bool
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        Text(text)
            .font(.system(size: 32, weight: .black))
            .foregroundColor(isPositive ? .yellow : .red)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .offset(y: offsetY)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2)) {
                    offsetY = -80
                    opacity = 0
                }
            }
    }
}

// MARK: - 春天全屏动画
struct SpringEffectView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.green.opacity(0.2 * opacity).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("🌸🌸🌸").font(.system(size: 60)).scaleEffect(scale)
                Text("春天!")
                    .font(.system(size: 56, weight: .black))
                    .foregroundColor(.green)
                    .shadow(color: .yellow, radius: 12)
                    .scaleEffect(scale)
                Text("翻倍!").font(.system(size: 24, weight: .bold)).foregroundColor(.yellow)
            }
        }
        .onAppear {
            VoiceAnnouncer.shared.speak("春天，翻倍")
            SoundManager.shared.play("win")
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { scale = 1.2 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.4)) { opacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { onDone() }
        }
    }
}
struct ShakeModifier: ViewModifier {
    let intensity: CGFloat
    @State private var offset: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .onAppear {
                let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
                    offset = CGSize(
                        width: CGFloat.random(in: -intensity...intensity),
                        height: CGFloat.random(in: -intensity...intensity)
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    timer.invalidate()
                    offset = .zero
                }
            }
    }
}

extension View {
    func shake(intensity: CGFloat = 8) -> some View {
        self.modifier(ShakeModifier(intensity: intensity))
    }
}

// MARK: - 腾讯式金色大按钮
struct TencentButton: View {
    let title: String
    let action: () -> Void
    var enabled: Bool = true
    var isPrimary: Bool = true

    var body: some View {
        Button(action: {
            SoundManager.shared.play("click")
            action()
        }) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isPrimary ? .black : .white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    isPrimary
                        ? LinearGradient(colors: [.yellow, Color(red: 0.95, green: 0.7, blue: 0.2)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(22)
                .shadow(color: isPrimary ? .orange.opacity(0.4) : .clear, radius: 6, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(isPrimary ? Color.white.opacity(0.4) : Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .scaleEffect(enabled ? 1 : 0.95)
    }
}

// MARK: - 顶栏：房号+倍数+菜单
struct GameTopBar: View {
    let roomId: String
    let multiplier: Int
    let onMenu: () -> Void

    var body: some View {
        HStack {
            // 房号
            HStack(spacing: 4) {
                Text("🏠").font(.system(size: 12))
                Text(roomId).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.black.opacity(0.35))
            .cornerRadius(12)

            Spacer()

            // 倍数
            if multiplier > 1 {
                MultiplierBadge(mult: multiplier)
            }

            Spacer()

            Button(action: onMenu) {
                Text("⚙️").font(.system(size: 18))
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
