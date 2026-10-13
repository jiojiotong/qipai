import Foundation

// MARK: - 牌
struct Card: Identifiable, Hashable {
    let id: Int
    var rank: Int { id < 52 ? 3 + (id >> 2) : (id == 52 ? 16 : 17) }
    var suit: Int { id < 52 ? id & 3 : 4 } // 0♠ 1♥ 2♣ 3♦ 4王
    var isRed: Bool { suit == 1 || suit == 3 }
    var rankText: String {
        switch rank {
        case 11: return "J"; case 12: return "Q"; case 13: return "K"
        case 14: return "A"; case 15: return "2"
        case 16: return "小王"; case 17: return "大王"
        default: return "\(rank)"
        }
    }
    var suitText: String {
        switch suit { case 0: return "♠"; case 1: return "♥"; case 2: return "♣"; case 3: return "♦"; default: return "" }
    }
}

// MARK: - 座位 / 出牌
struct SeatInfo {
    var name: String = ""
    var kind: String = ""
}

struct LastPlay {
    var seat: Int = -1
    var cards: [Card] = []
    var typeText: String = ""
}

struct TexasWinner {
    var seats: [Int] = []
    var amount: Int = 0
    var showdown: Bool = false
}

struct ChatBubble: Identifiable {
    let id = UUID()
    var from: String
    var text: String
}

/// 快捷聊天预设（须与服务端 CHAT_PHRASES 一致）
let chatPhrases = [
    "大家好，很高兴见到各位",
    "快点吧，我等到花儿都谢了",
    "哈哈，运气真好",
    "哎呀，打错了",
    "你太厉害了",
    "再来一局",
    "谢谢",
    "承让承让",
]

let playTypeNames: [String: String] = [
    "single": "单张", "pair": "对子", "trio": "三张",
    "trio1": "三带一", "trio2": "三带二", "straight": "顺子",
    "pairStraight": "连对", "plane": "飞机", "plane1": "飞机带翅",
    "plane2": "飞机带翅", "four2": "四带二",
    "bomb": "炸弹!", "rocket": "王炸!!"
]

// MARK: - JSON 小工具
func jsonDict(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}
func asInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    return nil
}
