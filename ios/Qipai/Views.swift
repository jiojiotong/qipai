import SwiftUI

let gold = Color(red: 0.79, green: 0.64, blue: 0.15)
let bgBlack = Color(red: 0.08, green: 0.08, blue: 0.08)
let feltGreen = LinearGradient(
    colors: [Color(red: 0.12, green: 0.35, blue: 0.2), Color(red: 0.08, green: 0.25, blue: 0.15)],
    startPoint: .top, endPoint: .bottom
)
let cardBack = Color(red: 0.13, green: 0.13, blue: 0.13)

// MARK: - 入口
struct RootView: View {
    @EnvironmentObject var client: GameClient
    var body: some View {
        Group {
            if !client.isLoggedIn { LoginView() }
            else if client.screen == "room" { RoomView() }
            else { LobbyView() }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 登录
struct LoginView: View {
    @EnvironmentObject var client: GameClient
    @State private var name = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 16) {
            Text("🃏").font(.system(size: 64))
            Text("棋牌室").font(.largeTitle).bold().foregroundColor(gold)
            TextField("服务器地址", text: $client.serverURL)
                .textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
            TextField("用户名", text: $name)
                .textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
            SecureField("密码", text: $password).textFieldStyle(.roundedBorder)
            if let e = client.errorMsg { Text(e).foregroundColor(.red).font(.footnote) }
            HStack(spacing: 12) {
                Button("登录") { go(false) }.buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                Button("注册") { go(true) }.buttonStyle(.bordered)
            }.disabled(busy || name.isEmpty || password.isEmpty)
            Text("首个注册的用户自动成为管理员").font(.footnote).foregroundColor(.gray)
            Spacer()
        }
        .padding(24)
        .background(bgBlack)
    }

    private func go(_ reg: Bool) {
        busy = true
        Task { await client.login(name: name, password: password, isRegister: reg); busy = false }
    }
}

// MARK: - 大厅
struct LobbyView: View {
    @EnvironmentObject var client: GameClient
    @State private var joinId = ""
    @State private var showSettings = false
    @State private var showGames = false
    @State private var txSeats = 6
    @State private var zhaSeats = 5
    @State private var frGame = 0  // 0 斗地主 1 德州 2 炸金花
    @State private var frSeats = 5
    @State private var frFree = false  // 记分模式
    let frGames = ["doudizhu", "texas", "zha"]
    let frGameNames = ["斗地主", "德州扑克", "炸金花"]

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("👋 \(client.userName)").font(.title2).bold()
                Spacer()
                Text("🪙 \(client.coins)").foregroundColor(gold).font(.title3).bold()
            }
            if !client.wsConnected { Text("连接中…").font(.footnote).foregroundColor(.gray) }
            VStack(spacing: 10) {
                Button("🃏 斗地主快速开始（单机+机器人）") { client.createRoom() }
                    .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                    .controlSize(.large)
                HStack {
                    Text("德州扑克").bold()
                    Stepper("\(txSeats)人桌", value: $txSeats, in: 2...9)
                        .frame(maxWidth: 150)
                    Button("开始") { client.createRoom(game: "texas", seats: txSeats) }
                        .buttonStyle(.bordered)
                }
                .font(.footnote)
                HStack {
                    Text("炸金花").bold()
                    Stepper("\(zhaSeats)人桌", value: $zhaSeats, in: 2...8)
                        .frame(maxWidth: 150)
                    Button("开始") { client.createRoom(game: "zha", seats: zhaSeats) }
                        .buttonStyle(.bordered)
                }
                .font(.footnote)
            }
            VStack {
                TextField("房间号（如 R1A2B3）", text: $joinId)
                    .textFieldStyle(.roundedBorder).autocapitalization(.allCharacters).disableAutocorrection(true)
                Button("加入朋友的房间") { if !joinId.isEmpty { client.joinRoom(joinId.uppercased()) } }
                    .buttonStyle(.bordered)
            }
            // 好友房
            VStack(spacing: 8) {
                Text("👥 创建好友房（等齐人再开）").font(.subheadline).bold()
                Picker("", selection: $frGame) {
                    ForEach(0..<3, id: \.self) { i in Text(frGameNames[i]).tag(i) }
                }
                .pickerStyle(.segmented)
                .onChange(of: frGame) { _ in
                    if frGame == 0 { frSeats = 3 } else if frGame == 1 { frSeats = 6 } else { frSeats = 5 }
                }
                HStack {
                    if frGame == 0 {
                        Text("3人桌（固定）").font(.footnote).foregroundColor(.gray)
                    } else {
                        Stepper("\(frSeats)人桌", value: $frSeats, in: 2...(frGame == 1 ? 9 : 8))
                            .font(.footnote)
                    }
                    Spacer()
                    Button("创建房间") {
                        let seats = frGame == 0 ? 3 : frSeats
                        client.createFriendRoom(game: frGames[frGame], seats: seats, free: frFree)
                    }
                    .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                }
                Toggle("📝 记分模式（0金币，只记输赢分）", isOn: $frFree)
                    .font(.footnote).tint(gold)
            }
            .padding(12)
            .background(cardBack).cornerRadius(12)
            if let r = client.reliefNotice {
                HStack {
                    Text(r).font(.footnote).foregroundColor(.white)
                    Spacer()
                    Button("✕") { client.reliefNotice = nil }.foregroundColor(.gray)
                }
                .padding(10).background(Color.green.opacity(0.85)).cornerRadius(8)
            }
            if let e = client.errorMsg { Text(e).foregroundColor(.red).font(.footnote) }
            Spacer()
            HStack {
                Button("⚙️ 设置") { showSettings = true }
                Spacer()
                Button("📊 战绩") { showGames = true }
                Spacer()
                Button("退出登录") { client.logout() }.foregroundColor(.red)
            }.font(.footnote)
        }
        .padding(24)
        .background(bgBlack)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(client)
        }
        .sheet(isPresented: $showGames) {
            MyGamesView()
                .environmentObject(client)
        }
        .onAppear { if !client.wsConnected { client.connectWS() }; Task { await client.refreshMe() } }
    }
}

// MARK: - 房间
struct RoomView: View {
    @EnvironmentObject var client: GameClient
    @State private var showChat = false
    private var gameNameText: String {
        switch client.gameKind {
        case "texas": return "德州扑克"
        case "zha": return "炸金花"
        default: return "斗地主"
        }
    }
    var body: some View {
        ZStack {
            feltGreen.ignoresSafeArea()
            if client.phase == "" {
                VStack(spacing: 16) {
                    Text(gameNameText).font(.title).bold().foregroundColor(gold)
                    HStack(spacing: 8) {
                        Text("房号 \(client.roomId ?? "")")
                            .font(.title2).bold()
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(cardBack).cornerRadius(10)
                        Button("复制") {
                            UIPasteboard.general.string = client.roomId ?? ""
                        }.font(.footnote)
                    }
                    Text("把房号发给朋友，对方在大厅输入房号加入").font(.caption).foregroundColor(.gray)
                    if client.isFree {
                        Text("📝 记分模式：只记输赢分，不输赢金币").font(.caption).foregroundColor(gold)
                    }
                    ForEach(0..<client.seats.count, id: \.self) { i in
                        if i < client.seats.count {
                            let s = client.seats[i]
                            Text("\(s.kind == "bot" ? "🤖" : (s.name.isEmpty ? "💺" : "🧑")) \(s.name.isEmpty ? "空位" : s.name)")
                        }
                    }
                    Button("开始游戏") { client.startGame() }
                        .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                    Button("离开房间") { client.leaveRoom() }.foregroundColor(.gray)
                }
            } else {
                if client.gameKind == "texas" { TexasTableView() }
                else if client.gameKind == "zha" { ZhaTableView() }
                else { DoudizhuTableView() }
            }
            if !client.wsConnected {
                VStack {
                    HStack {
                        Text("📡 连接断开，重连中…").font(.footnote).foregroundColor(.white)
                        Spacer()
                        Button("重试") { client.connectWS() }.font(.footnote).foregroundColor(gold)
                    }
                    .padding(10).background(Color.orange.opacity(0.85)).cornerRadius(8)
                    .padding()
                    Spacer()
                }
            }
            if client.phase != "" && client.isFree {
                VStack {
                    HStack {
                        Spacer()
                        Text("📝 记分").font(.caption2).bold()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(0.6)).cornerRadius(8)
                            .foregroundColor(gold)
                            .padding(.top, 4).padding(.trailing, 8)
                    }
                    Spacer()
                }
            }
            if let b = client.chatBubble {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(b.from).font(.caption2).foregroundColor(.gray)
                            Text(b.text)
                                .font(.subheadline)
                                .padding(10)
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                        .padding()
                    }
                    Spacer().frame(height: 140)
                }
                .transition(.opacity)
            }
            if client.phase != "" {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("💬") { showChat = true }
                            .font(.title2)
                            .padding(10)
                            .background(cardBack.opacity(0.9))
                            .clipShape(Circle())
                            .padding()
                    }
                    Spacer().frame(height: 200)
                }
            }
            if let e = client.errorMsg {
                VStack {
                    HStack {
                        Text(e).font(.footnote).foregroundColor(.white)
                        Spacer()
                        Button("✕") { client.errorMsg = nil }.foregroundColor(.gray)
                    }
                    .padding(10).background(Color.red.opacity(0.85)).cornerRadius(8)
                    .padding()
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showChat) {
            VStack(spacing: 0) {
                Text("快捷聊天").font(.headline).padding()
                List(chatPhrases, id: \.self) { p in
                    Button(p) {
                        client.sendChat(p)
                        showChat = false
                    }
                    .foregroundColor(.white)
                }
                .listStyle(.plain)
            }
            .background(bgBlack)
        }
    }
}

// MARK: - 斗地主牌桌
struct DoudizhuTableView: View {
    @EnvironmentObject var client: GameClient
    @State private var selected: Set<Int> = Set()
    @State private var passHint = false
    @State private var showBomb = false
    @State private var showRocket = false
    @State private var showChat = false
    @State private var lastPlayId = ""

    var oppA: Int { (client.mySeat + 1) % 3 }
    var oppB: Int { (client.mySeat + 2) % 3 }

    var body: some View {
        VStack(spacing: 8) {
            // 对手
            HStack {
                OpponentView(seat: oppA)
                Spacer()
                VStack(spacing: 2) {
                    Text("底牌").font(.caption).foregroundColor(.gray)
                    if !client.bottom.isEmpty {
                        HStack(spacing: 4) { ForEach(client.bottom) { MiniCard(card: $0) } }
                    }
                }
                Spacer()
                OpponentView(seat: oppB)
            }
            .padding(.horizontal)

            Spacer()

            // 桌面出的牌
            VStack(spacing: 4) {
                if let lp = client.lastPlay, !lp.cards.isEmpty {
                    Text("\(seatName(lp.seat))：\(lp.typeText)")
                        .font(.caption).foregroundColor(lp.typeText.contains("炸") ? .red : .gray)
                    HStack(spacing: -14) { ForEach(lp.cards) { CardView(card: $0) } }
                } else if client.phase == "play" {
                    Text("轮到 \(seatName(client.turn)) 出牌").font(.caption).foregroundColor(.gray)
                }
            }
            .frame(minHeight: 120)

            Spacer()

            // 自己
            VStack(spacing: 8) {
                HStack {
                    if client.landlord == client.mySeat { Text("👑 地主").foregroundColor(gold).bold() }
                    Text("我的手牌（\(client.hand.count)）").font(.caption).foregroundColor(.gray)
                    if client.phase == "play" && client.turn == client.mySeat {
                        Text("轮到你出牌").font(.caption).bold().foregroundColor(gold)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: -28) {
                        ForEach(client.hand) { card in
                            CardView(card: card, selected: selected.contains(card.id))
                                .onTapGesture { toggle(card.id) }
                        }
                    }.padding(.horizontal, 16).padding(.top, 14)
                }
                actionButtons
            }
            .padding(.bottom, 8)
        }
        .onChange(of: client.turn) { _ in selected.removeAll() }
        .onChange(of: client.phase) { _ in selected.removeAll() }
        .onChange(of: client.hintCards) { cards in
            if cards.isEmpty {
                // 空提示 = 建议不出
                if client.phase == "play" && client.turn == client.mySeat && client.lastPlay != nil {
                    passHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { passHint = false }
                }
            } else {
                selected = Set(cards)
            }
        }
        .overlay { if client.phase == "over" { GameOverView() } }
    }

    private func seatName(_ i: Int) -> String {
        if i == client.mySeat { return "你" }
        if i < client.seats.count && !client.seats[i].name.isEmpty { return client.seats[i].name }
        return "玩家\(i)"
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if client.phase == "bid" && client.bidTurn == client.mySeat {
                let bidMax = client.bids.compactMap { $0 }.max() ?? 0
                Button("不叫") {
                    client.bid(0)
                    SoundManager.shared.play("click")
                    VoiceAnnouncer.shared.speak("不叫")
                }.buttonStyle(.bordered)
                if bidMax < 3 {
                    ForEach((bidMax + 1)...3, id: \.self) { s in
                        Button("\(s)分") {
                            client.bid(s)
                            SoundManager.shared.play("click")
                            VoiceAnnouncer.shared.speak("叫\(s)分")
                        }
                            .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                    }
                }
            } else if client.phase == "play" && client.turn == client.mySeat {
                if client.lastPlay != nil {
                    Button("不出") {
                        client.pass()
                        SoundManager.shared.play("click")
                        VoiceAnnouncer.shared.speak("不出")
                    }.buttonStyle(.bordered)
                }
                Button("提示") { client.requestHint() }.buttonStyle(.bordered)
                if passHint {
                    Text("💡 建议不出").font(.caption).foregroundColor(gold)
                }
                Button("出牌") {
                    let cards = selected.sorted()
                    client.playCards(cards)
                    selected.removeAll()
                    // 炸弹/火箭特殊音效+播报
                    if cards.count == 4 || (cards.count == 2 && cards.allSatisfy({ $0.rank >= 16 })) {
                        SoundManager.shared.play("bomb")
                        VoiceAnnouncer.shared.speak("炸弹")
                    } else {
                        SoundManager.shared.play("deal")
                    }
                }
                .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                .disabled(selected.isEmpty)
            } else {
                Button("💬") { showChat = true }
                    .font(.title2)
                    .padding(8)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(20)
                Button("离开") { client.leaveRoom() }.font(.footnote).foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
    }
    .overlay(
        Group {
            if showBomb {
                BombEffectView { showBomb = false }
            }
            if showRocket {
                RocketEffectView { showRocket = false }
            }
        }
    )
    .sheet(isPresented: $showChat) {
        QuickChatView(isShown: $showChat)
            .environmentObject(client)
    }
    .onChange(of: client.lastPlay?.cards.count) { _ in
        // 检测炸弹/火箭
        if let lp = client.lastPlay {
            let playKey = lp.cards.map { String($0.id) }.joined(separator: ",")
            if playKey != lastPlayId {
                lastPlayId = playKey
                if lp.cards.count == 4 {
                    showBomb = true
                } else if lp.cards.count == 2 && lp.cards.allSatisfy({ $0.rank >= 16 }) {
                    showRocket = true
                }
            }
        }
    }
}

struct OpponentView: View {
    @EnvironmentObject var client: GameClient
    let seat: Int

    private var avatar: String {
        let avatars = ["😎", "🤓", "😜", "🤠", "🥳", "😇", "🤖", "👾"]
        let name = seat < client.seats.count ? client.seats[seat].name : ""
        let h = abs(name.hashValue) % avatars.count
        return avatars[h]
    }

    var body: some View {
        VStack(spacing: 4) {
            PlayerPanelView(
                name: seat < client.seats.count ? client.seats[seat].name : "",
                coins: 0,
                cardCount: seat < client.handCounts.count ? client.handCounts[seat] : 0,
                isLandlord: client.landlord == seat,
                isTurn: (client.turn == seat && client.phase == "play") || (client.bidTurn == seat && client.phase == "bid"),
                avatar: avatar
            )
            if client.phase == "bid", seat < client.bids.count, let b = client.bids[seat] {
                Text(b == 0 ? "不叫" : "叫\(b)分")
                    .font(.caption).bold().foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(b == 0 ? Color.gray.opacity(0.6) : gold.opacity(0.9))
                    .cornerRadius(10)
            }
            if client.turn == seat && client.phase == "play" {
                Text("思考中…").font(.caption2).foregroundColor(gold)
            }
            if client.bidTurn == seat && client.phase == "bid" {
                Text("叫分中…").font(.caption2).foregroundColor(gold)
            }
        }
        .frame(width: 90)
    }
}

// MARK: - 结算
struct GameOverView: View {
    @EnvironmentObject var client: GameClient
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(client.resultInfo).font(.title).bold()
                if client.isFree {
                    Text("📝 记分模式").font(.caption).foregroundColor(gold)
                }
                ForEach(0..<min(client.resultDeltas.count, client.seats.count), id: \.self) { i in
                    let d = client.resultDeltas[i]
                    Text("\(i < client.seats.count ? client.seats[i].name : "")  \(d >= 0 ? "+" : "")\(d)")
                        .foregroundColor(d >= 0 ? .green : .red)
                }
                if client.isFree {
                    Text("本局为记分，金币不变").font(.caption).foregroundColor(.gray)
                } else {
                    Text("🪙 余额 \(client.coins)").foregroundColor(gold)
                }
                Button("再来一局") { client.startGame() }
                    .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
                Button("返回大厅") { client.leaveRoom() }.foregroundColor(.gray)
            }
            .padding(28)
            .background(cardBack).cornerRadius(16)
            .padding(40)
        }
    }
}

// MARK: - 牌
// (CardView/MiniCard 已移至 CardDesign.swift)
