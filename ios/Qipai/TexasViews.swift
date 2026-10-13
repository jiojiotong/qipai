
// MARK: - 德州扑克牌桌
let txStreetNames: [String: String] = [
    "preflop": "翻牌前", "flop": "翻牌", "turn": "转牌",
    "river": "河牌", "showdown": "摊牌", "over": "结束"
]

struct TexasTableView: View {
    @EnvironmentObject var client: GameClient
    @State private var showRaise = false

    var n: Int { client.seats.count }
    var oppSeats: [Int] {
        (0..<n).filter { $0 != client.mySeat }
            .sorted { (($0 - client.mySeat + n) % n) < (($1 - client.mySeat + n) % n) }
    }
    var myTurn: Bool { client.txActor == client.mySeat && client.phase != "over" }

    var body: some View {
        VStack(spacing: 6) {
            // 对手
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(oppSeats, id: \.self) { s in TxOpponentView(seat: s) }
                }.padding(.horizontal)
            }

            Spacer()

            // 公共牌 + 底池
            VStack(spacing: 6) {
                Text("底池 🪙 \(client.txPot)").font(.headline).bold().foregroundColor(gold)
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        if i < client.txBoard.count { MiniCard(card: client.txBoard[i]) }
                        else {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12))
                                .frame(width: 30, height: 42)
                        }
                    }
                }
                Text(txStreetNames[client.txStreet] ?? "").font(.caption).foregroundColor(.gray)
            }
            .frame(minHeight: 110)

            Spacer()

            // 自己
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(client.txHole) { CardView(card: $0) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("你 \(client.userName)").font(.subheadline).bold()
                        if client.mySeat < client.txStacks.count {
                            Text("🪙 \(client.txStacks[client.mySeat])").font(.caption).foregroundColor(gold)
                        }
                        if client.txButton == client.mySeat { Text("庄家 D").font(.caption2).foregroundColor(gold) }
                        if myTurn { Text("轮到你行动").font(.caption).bold().foregroundColor(gold) }
                        else if client.txActor >= 0 && client.phase != "over" {
                            Text("等待 \(seatName(client.txActor))…").font(.caption2).foregroundColor(.gray)
                        }
                    }
                }
                actionBar
            }
            .padding(.bottom, 8)
        }
        .overlay { if client.phase == "over" { TexasOverView() } }
        .onChange(of: client.txActor) { _ in showRaise = false }
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
                if showRaise {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            let opts = raiseOptions()
                            ForEach(opts.indices, id: \.self) { i in
                                Button(opts[i].0) { client.txAct("raise", amount: opts[i].1); showRaise = false }
                                    .buttonStyle(.bordered)
                            }
                        }.padding(.horizontal)
                    }
                }
                HStack(spacing: 12) {
                    Button("弃牌") { client.txAct("fold") }.buttonStyle(.bordered)
                    Button("💡") { client.requestHint() }.buttonStyle(.bordered)
                    if client.txToCall == 0 {
                        Button("过牌") { client.txAct("check") }.buttonStyle(.bordered)
                    } else {
                        Button("跟 \(client.txToCall)") { client.txAct("call") }
                            .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                    }
                    Button(showRaise ? "取消" : "加注") { showRaise.toggle() }.buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
        } else {
            Button("离开") { client.leaveRoom() }.font(.footnote).foregroundColor(.gray)
        }
    }

    private func raiseOptions() -> [(String, Int)] {
        let myBet = client.mySeat < client.txRoundBet.count ? client.txRoundBet[client.mySeat] : 0
        let myStack = client.mySeat < client.txStacks.count ? client.txStacks[client.mySeat] : 0
        let allIn = myBet + myStack
        let min = client.txMinRaiseTo
        var opts: [(String, Int)] = []
        if min > 0 && min < allIn { opts.append(("最小 \(min)", min)) }
        let half = max(min, client.txToCall + max(client.txBB, client.txPot / 2))
        if half > min && half < allIn { opts.append(("半池 \(half)", half)) }
        let full = max(min, client.txToCall + max(client.txBB, client.txPot))
        if full > half && full < allIn { opts.append(("满池 \(full)", full)) }
        if allIn > 0 { opts.append(("全下 \(allIn)", allIn)) }
        return opts
    }
}

struct TxOpponentView: View {
    @EnvironmentObject var client: GameClient
    let seat: Int

    var body: some View {
        let folded = seat < client.txFolded.count && client.txFolded[seat]
        let stack = seat < client.txStacks.count ? client.txStacks[seat] : 0
        let bet = seat < client.txRoundBet.count ? client.txRoundBet[seat] : 0
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if client.txButton == seat {
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
                else { Text("🂠").font(.title2) }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(client.txActor == seat && client.phase != "over" ? gold : Color.clear, lineWidth: 2)
            )
            Text("🪙\(stack)").font(.caption2).foregroundColor(.gray)
            if bet > 0 {
                Text("注 \(bet)").font(.caption2).foregroundColor(gold).bold()
            }
        }
        .frame(width: 76)
        .opacity(folded ? 0.45 : 1)
    }
}

// MARK: - 德州结算
struct TexasOverView: View {
    @EnvironmentObject var client: GameClient
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    Text(client.resultInfo).font(.title).bold()
                    ForEach(client.txWinners.indices, id: \.self) { i in
                        let w = client.txWinners[i]
                        VStack(spacing: 4) {
                            let names = w.seats.map { seatName($0) }.joined(separator: "、")
                            let hand = w.seats.first.flatMap {
                                $0 < client.txHandNames.count ? client.txHandNames[$0] : nil
                            } ?? ""
                            Text("\(names) 赢 🪙\(w.amount)\(hand.isEmpty ? "" : "（\(hand)）")")
                                .font(.subheadline).bold().foregroundColor(gold)
                            if w.showdown {
                                HStack(spacing: 8) {
                                    ForEach(w.seats, id: \.self) { s in
                                        if s < client.txHoleCards.count {
                                            HStack(spacing: 2) {
                                                ForEach(client.txHoleCards[s]) { MiniCard(card: $0) }
                                            }
                                        }
                                    }
                                }
                            }
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
