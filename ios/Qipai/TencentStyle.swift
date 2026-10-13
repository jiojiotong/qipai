import SwiftUI

// MARK: - 腾讯风格：玩家头像面板
struct PlayerPanelView: View {
    let name: String
    let coins: Int
    let cardCount: Int
    let isLandlord: Bool
    let isTurn: Bool
    let avatar: String  // emoji 头像

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // 头像框
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isTurn ? [.yellow, .orange] : [.gray.opacity(0.3), .gray.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: isTurn ? .yellow.opacity(0.5) : .clear, radius: 6)

                Circle()
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                    .frame(width: 54, height: 54)

                Text(avatar)
                    .font(.system(size: 28))

                if isLandlord {
                    Text("👑")
                        .font(.system(size: 16))
                        .offset(x: 20, y: -22)
                }
            }

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 80)

            // 金币
            HStack(spacing: 2) {
                Text("🪙").font(.system(size: 10))
                Text("\(coins)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(gold)
            }

            // 牌数
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 44, height: 30)
                Text("\(cardCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 90)
        .scaleEffect(isTurn ? 1.08 : 1.0)
        .animation(.spring(response: 0.3), value: isTurn)
    }
}

// MARK: - 倒计时圆环
struct CountdownRing: View {
    let progress: Double  // 0~1
    let seconds: Int
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)
                .frame(width: 36, height: 36)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progress > 0.3 ? Color.green : Color.red,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Text("\(seconds)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - 炸弹特效
struct BombEffectView: View {
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 1.0
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.red.opacity(0.25 * opacity)
                .ignoresSafeArea()
            VStack {
                Text("💥")
                    .font(.system(size: 120))
                    .scaleEffect(scale)
                Text("炸弹!")
                    .font(.system(size: 48, weight: .black))
                    .foregroundColor(.red)
                    .shadow(color: .yellow, radius: 10)
                    .scaleEffect(scale)
            }
        }
        .onAppear {
            SoundManager.shared.play("bomb")
            VoiceAnnouncer.shared.speak("炸弹")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.5
                    opacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                onDone()
            }
        }
    }
}

// MARK: - 火箭特效
struct RocketEffectView: View {
    @State private var offsetY: CGFloat = 300
    @State private var opacity: Double = 1.0
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.orange.opacity(0.2 * opacity)
                .ignoresSafeArea()
            VStack {
                Text("🚀")
                    .font(.system(size: 100))
                    .offset(y: offsetY)
                Text("火箭!")
                    .font(.system(size: 48, weight: .black))
                    .foregroundColor(.orange)
                    .shadow(color: .yellow, radius: 10)
            }
        }
        .onAppear {
            SoundManager.shared.play("bomb")
            VoiceAnnouncer.shared.speak("火箭")
            withAnimation(.easeOut(duration: 0.6)) {
                offsetY = -100
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                onDone()
            }
        }
    }
}

// MARK: - 快捷聊天
struct QuickChatView: View {
    @EnvironmentObject var client: GameClient
    @Binding var isShown: Bool

    let phrases = [
        ("👋", "大家好!"),
        ("😄", "哈哈，手气不错"),
        ("😅", "哎呀，打错了"),
        ("🤝", "合作愉快"),
        ("⚡️", "快点出牌"),
        ("👍", "打得漂亮"),
        ("🍀", "祝好运"),
        ("💪", "加油"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("快捷聊天").font(.headline).foregroundColor(.white)
                Spacer()
                Button("✕") { isShown = false }.foregroundColor(.gray)
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(phrases, id: \.1) { emoji, text in
                    Button(action: {
                        client.sendChat("\(emoji) \(text)")
                        VoiceAnnouncer.shared.speak(text)
                        isShown = false
                    }) {
                        HStack {
                            Text(emoji)
                            Text(text).font(.system(size: 13))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16).opacity(0.95))
        .cornerRadius(16)
        .padding()
    }
}

// MARK: - 倍数徽章
struct MultiplierBadge: View {
    let mult: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("✖️")
            Text("\(mult)倍")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.yellow)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            LinearGradient(colors: [.red.opacity(0.8), .orange.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        )
        .cornerRadius(14)
        .shadow(color: .orange.opacity(0.5), radius: 4)
    }
}

// MARK: - 聊天消息气泡
struct ChatBubbleView: View {
    let text: String
    @State private var opacity: Double = 1.0

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white)
            .cornerRadius(12)
            .opacity(opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { opacity = 0 }
                }
            }
    }
}
