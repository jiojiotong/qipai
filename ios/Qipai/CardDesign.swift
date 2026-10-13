import SwiftUI
import AVFoundation

// MARK: - 精美扑克牌面
struct CardView: View {
    let card: Card
    var selected: Bool = false
    var small: Bool = false

    private var w: CGFloat { small ? 40 : 58 }
    private var h: CGFloat { small ? 56 : 82 }
    private var fg: Color { (card.isRed || card.rank >= 16) ? .red : .black }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: small ? 6 : 10)
                .fill(
                    LinearGradient(
                        colors: [.white, Color(white: 0.94)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 1, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: small ? 6 : 10)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )
            if card.rank >= 16 {
                // 大小王：竖排文字
                VStack(spacing: 2) {
                    Text(card.rank == 17 ? "大" : "小")
                        .font(.system(size: small ? 13 : 20, weight: .black))
                    Text("王")
                        .font(.system(size: small ? 13 : 20, weight: .black))
                    Text("🃏").font(.system(size: small ? 12 : 18))
                }
                .foregroundColor(fg)
            } else {
                // 左上角角标
                VStack(spacing: 0) {
                    Text(card.rankText)
                        .font(.system(size: small ? 11 : 16, weight: .bold))
                    Text(card.suitText)
                        .font(.system(size: small ? 10 : 14))
                }
                .foregroundColor(fg)
                .position(x: small ? 12 : 16, y: small ? 14 : 20)
                // 右下角角标（旋转180°）
                VStack(spacing: 0) {
                    Text(card.rankText)
                        .font(.system(size: small ? 11 : 16, weight: .bold))
                    Text(card.suitText)
                        .font(.system(size: small ? 10 : 14))
                }
                .foregroundColor(fg)
                .rotationEffect(.degrees(180))
                .position(x: w - (small ? 12 : 16), y: h - (small ? 14 : 20))
                // 中央大花色
                Text(card.suitText)
                    .font(.system(size: small ? 22 : 34))
                    .foregroundColor(fg.opacity(0.9))
            }
        }
        .frame(width: w, height: h)
        .offset(y: selected ? -16 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
    }
}

// MARK: - 牌背
struct CardBackView: View {
    var small: Bool = false
    private var w: CGFloat { small ? 40 : 58 }
    private var h: CGFloat { small ? 56 : 82 }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: small ? 6 : 10)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.25, blue: 0.55), Color(red: 0.1, green: 0.15, blue: 0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 1, y: 2)
            RoundedRectangle(cornerRadius: small ? 6 : 10)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: w - 8, height: h - 8)
            Text("🃏").font(.system(size: small ? 16 : 26)).opacity(0.7)
        }
        .frame(width: w, height: h)
    }
}

struct MiniCard: View {
    let card: Card
    var body: some View { CardView(card: card, small: true) }
}

// MARK: - 音效
class SoundManager: ObservableObject {
    static let shared = SoundManager()
    private var players: [AVAudioPlayer] = []

    func play(_ name: String) {
        // 使用系统音效，name: "click" | "deal" | "win" | "lose" | "bomb"
        let id: SystemSoundID
        switch name {
        case "deal": id = 1105  // 发牌
        case "click": id = 1104 // 点击
        case "win": id = 1025   // 胜利
        case "lose": id = 1026  // 失败
        case "bomb": id = 1106  // 炸弹
        default: id = 1104
        }
        AudioServicesPlaySystemSound(id)
    }
}

// MARK: - 语音播报
class VoiceAnnouncer: ObservableObject {
    static let shared = VoiceAnnouncer()
    private let synth = AVSpeechSynthesizer()
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "voiceEnabled") }
    }

    func speak(_ text: String) {
        guard enabled else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.55
        synth.speak(u)
    }
}
