import SwiftUI

// MARK: - 炸金花牌桌
struct ZhaTableView: View {
    @EnvironmentObject var client: GameClient
    @State private var compareTarget: Int? = nil

    var n: Int { client.seats.count }
    var oppSeats: [Int] {
        (0..<n).filter { $0 != client.mySeat }
            .sorted { (($0 - client.mySeat + n) % n) < (($1 - client.mySeat + n) % n) }
    }
    var myTurn: Bool { client.zhaActor == client.mySeat && client.phase != "over" }
    var looked: Bool {
        client.mySeat < client.zhaLooked.count && client.zhaLooked[client.mySeat]
    }

    var body: some View {
        VStack(spacing: 6) {
            // 对手（点选比牌目标）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(oppSeats, id: \.self) { s in
                        ZhaOpponentView(seat: s, selected: compareTarget == s)
                            .onTapGesture {
                                if !(s < client.zhaFolded.count && client.zhaFolded[s]) {
                                    compareTarget = (compareTarget == s) ? nil : s
                                }
                            }
                    }
                }.padding(.horizontal)
            }

            Spacer()

            // 底池与注额
            VStack(spacing: 6) {
                Text("底池 🪙 \(client.zhaPot)").font(.headline).bold().foregroundColor(gold)
                Text("当前注 \(client.zhaBetLevel) 档（\(client.zhaBase)/注）")
                    .font(.caption).foregroundColor(.gray)
                if compareTarget != nil {
                    Text("比牌目标：\(seatName(compareTarget!))（再点取消）")
                        .font(.caption).foregroundColor(gold)
                }
            }
            .frame(minHeight: 80)

            Spacer()

            // 自己
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if looked {
                        ForEach(client.zhaHole) { CardView(card: $0) }
                    } else {
                        ForEach(0..<3, id: \.self) { _ in
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.7))
                                    .frame(width: 54, height: 76)
                                Text("🂠").font(.title)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("你 \(client.userName)").font(.subheadline).bold()
                        if client.mySeat < client.zhaStacks.count {
                            Text("🪙 \(client.zhaStacks[client.mySeat])").font(.caption).foregroundColor(gold)
                        }
                        Text(looked ? "👀 已看牌（2倍注）" : "🌙 闷牌中（1倍注）")
                            .font(.caption2).foregroundColor(.gray)
                        if myTurn { Text("轮到你行动").font(.caption).bold().foregroundColor(gold) }
                        else if client.zhaActor >= 0 && client.phase != "over" {
                            Text("等待 \(seatName(client.zhaActor))…").font(.caption2).foregroundColor(.gray)
                        }
                    }
                }
                actionBar
            }
            .padding(.bottom, 8)
        }
        .overlay { if client.phase == "over" { ZhaOverView() } }
        .onChange(of: client.zhaActor) { _ in compareTarget = nil }
    }

    private func seatName(_ i: Int) -> String {
        if i == client.mySeat { return "你" }
        if i < client.seats.count && !client.seats[i].name.isEmpty { return client.seats[i].name }
        return "玩家\(i)"
    }

    @ViewBuilder
    private var actionBar: some View {
        if myTurn {
            VStack(spacing: 8) {
                if let ht = client.hintText {
                    Text("💡 \(ht)").font(.caption).foregroundColor(gold)
                }
                HStack(spacing: 10) {
                    Button("弃牌") { client.zhaAct("fold") }.buttonStyle(.bordered)
                    Button("💡") { client.requestHint() }.buttonStyle(.bordered)
                    if !looked {
                        Button("看牌") { client.zhaAct("look") }.buttonStyle(.bordered)
                    }
                    Button("跟 \(client.zhaCallAmount)") { client.zhaAct("call") }
                        .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                    Button("加注") { client.zhaAct("raise") }.buttonStyle(.bordered)
                    Button("比牌 \(client.zhaCompareCost)") {
                        let t = compareTarget ?? client.zhaPrevAlive(client.mySeat)
                        if t >= 0 { client.zhaAct("compare", target: t); compareTarget = nil }
                    }.buttonStyle(.bordered)
                }
                .font(.footnote)
                .padding(.horizontal)
            }
        } else {
            Button("离开") { client.leaveRoom() }.font(.footnote).foregroundColor(.gray)
        }
    }
}

struct ZhaOpponentView: View {
    @EnvironmentObject var client: GameClient
    let seat: Int
    let selected: Bool

    var body: some View {
        let folded = seat < client.zhaFolded.count && client.zhaFolded[seat]
        let looked = seat < client.zhaLooked.count && client.zhaLooked[seat]
        let stack = seat < client.zhaStacks.count ? client.zhaStacks[seat] : 0
        let committed = seat < client.zhaCommitted.count ? client.zhaCommitted[seat] : 0
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if client.zhaButton == seat {
                    Text("D").font(.caption2).bold().foregroundColor(.black)
                        .frame(width: 16, height: 16).background(Color.white).cornerRadius(8)
                }
                Text(seat < client.seats.count ? client.seats[seat].name : "").font(.caption).bold()
                    .lineLimit(1)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(folded ? Color.gray.opacity(0.3) : Color.blue.opacity(0.7))
                    .frame(width: 40, height: 56)
                if folded { Text("弃").foregroundColor(.white).bold() }
                else {
                    VStack(spacing: 0) {
                        Text("🂠").font(.title2)
                        Text(looked ? "👀" : "🌙").font(.caption2)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.red : (client.zhaActor == seat && client.phase != "over" ? gold : Color.clear), lineWidth: 2)
            )
            Text("🪙\(stack)").font(.caption2).foregroundColor(.gray)
            if committed > 0 {
                Text("已下 \(committed)").font(.caption2).foregroundColor(gold)
            }
        }
        .frame(width: 76)
        .opacity(folded ? 0.45 : 1)
    }
}

// MARK: - 炸金花结算
struct ZhaOverView: View {
    @EnvironmentObject var client: GameClient
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    Text(client.resultInfo).font(.title).bold()
                    if client.zhaWinner >= 0 {
                        let w = client.zhaWinner
                        let hand = w < client.zhaHandNames.count ? client.zhaHandNames[w] : ""
                        Text("🏆 \(seatName(w)) 获胜\(hand.isEmpty ? "" : "（\(hand)）")")
                            .font(.headline).foregroundColor(gold)
                        if client.zhaShowdown && w < client.zhaHandNames.count {
                            Text(client.zhaShowdown ? "（亮牌比大小）" : "").font(.caption).foregroundColor(.gray)
                        }
                    }
                    ForEach(0..<min(client.resultDeltas.count, client.seats.count), id: \.self) { i in
                        let d = client.resultDeltas[i]
                        Text("\(seatName(i))  \(d >= 0 ? "+" : "")\(d)")
                            .foregroundColor(d >= 0 ? .green : .red).font(.footnote)
                    }
                    Text("🪙 余额 \(client.coins)").foregroundColor(gold)
                    Button("再来一局") { client.startGame() }
                        .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                    Button("返回大厅") { client.leaveRoom() }.foregroundColor(.gray)
                }
                .padding(24)
            }
            .background(cardBack).cornerRadius(16)
            .padding(32)
        }
    }

    private func seatName(_ i: Int) -> String {
        if i == client.mySeat { return "你" }
        if i < client.seats.count && !client.seats[i].name.isEmpty { return client.seats[i].name }
        return "玩家\(i)"
    }
}
