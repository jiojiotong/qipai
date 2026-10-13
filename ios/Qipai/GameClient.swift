import Foundation
import Combine

/// 与后端 WebSocket/HTTP 对接，持有全部对局状态。所有 @Published 更新都在主线程。
class GameClient: ObservableObject {
    @Published var screen: String = "login"          // login | lobby | room
    @Published var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? "https://ddz.anyther.top"
    @Published var token: String? = UserDefaults.standard.string(forKey: "token")
    @Published var userName: String = UserDefaults.standard.string(forKey: "userName") ?? ""
    @Published var userId: Int = UserDefaults.standard.integer(forKey: "userId")
    @Published var coins: Int = 0
    @Published var errorMsg: String? = nil
    @Published var wsConnected: Bool = false
    @Published var chatBubble: ChatBubble? = nil
    @Published var hintCards: [Int] = []
    @Published var hintText: String? = nil
    @Published var reliefNotice: String? = nil
    @Published var isFree = false  // 记分模式：不输赢金币

    // 房间
    @Published var roomId: String? = nil
    @Published var seats: [SeatInfo] = []
    @Published var mySeat: Int = 0

    // 对局
    @Published var phase: String = ""               // bid | play | over | ""
    @Published var gameKind: String = "doudizhu"    // doudizhu | texas
    @Published var hand: [Card] = []
    @Published var handCounts: [Int] = [0, 0, 0]
    @Published var landlord: Int = -1
    @Published var turn: Int = -1
    @Published var bidTurn: Int = -1
    @Published var bids: [Int?] = [nil, nil, nil]
    @Published var bottom: [Card] = []
    @Published var lastPlay: LastPlay? = nil
    @Published var resultDeltas: [Int] = []
    @Published var resultInfo: String = ""

    // 德州扑克
    @Published var txStreet: String = ""
    @Published var txBoard: [Card] = []
    @Published var txHole: [Card] = []
    @Published var txStacks: [Int] = []
    @Published var txFolded: [Bool] = []
    @Published var txRoundBet: [Int] = []
    @Published var txPot: Int = 0
    @Published var txToCall: Int = 0
    @Published var txMinRaiseTo: Int = 0
    @Published var txActor: Int = -1
    @Published var txButton: Int = 0
    @Published var txBB: Int = 0
    @Published var txWinners: [TexasWinner] = []
    @Published var txHandNames: [String] = []
    @Published var txHoleCards: [[Card]] = []

    // 炸金花
    @Published var zhaHole: [Card] = []
    @Published var zhaLooked: [Bool] = []
    @Published var zhaFolded: [Bool] = []
    @Published var zhaStacks: [Int] = []
    @Published var zhaCommitted: [Int] = []
    @Published var zhaPot: Int = 0
    @Published var zhaBetLevel: Int = 1
    @Published var zhaCallAmount: Int = 0
    @Published var zhaCompareCost: Int = 0
    @Published var zhaActor: Int = -1
    @Published var zhaButton: Int = 0
    @Published var zhaBase: Int = 0
    @Published var zhaWinner: Int = -1
    @Published var zhaShowdown: Bool = false
    @Published var zhaHandNames: [String] = []

    private var ws: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    private var manualClose = false // 用户主动退出/登录失效时不自动重连

    var isLoggedIn: Bool { token != nil }

    // MARK: - HTTP
    private func http(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        var base = serverURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path) else { throw NSError(domain: "url", code: -1) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let b = body { req.httpBody = try JSONSerialization.data(withJSONObject: b) }
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(domain: "json", code: -2, userInfo: [NSLocalizedDescriptionKey: "服务器返回异常"])
        }
        if let e = j["error"] as? String { throw NSError(domain: "api", code: -3, userInfo: [NSLocalizedDescriptionKey: e]) }
        return j
    }

    @MainActor
    func login(name: String, password: String, isRegister: Bool) async {
        errorMsg = nil
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        do {
            let j = try await http(isRegister ? "/api/register" : "/api/login", method: "POST",
                                   body: ["name": name, "password": password])
            guard let t = j["token"] as? String, let u = j["user"] as? [String: Any] else { return }
            token = t
            userName = (u["name"] as? String) ?? name
            userId = asInt(u["id"]) ?? 0
            coins = asInt(u["coins"]) ?? 0
            UserDefaults.standard.set(t, forKey: "token")
            UserDefaults.standard.set(userName, forKey: "userName")
            UserDefaults.standard.set(userId, forKey: "userId")
            screen = "lobby"
            connectWS()
            await refreshMe()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    @MainActor
    func logout() {
        manualClose = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        Task { try? await self.http("/api/logout", method: "POST") }
        ws?.cancel()
        ws = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: "token")
        screen = "login"
        roomId = nil
        wsConnected = false
    }

    /// token 失效：清掉登录态回登录页
    private func handleAuthExpired() {
        manualClose = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        ws?.cancel()
        ws = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: "token")
        roomId = nil
        screen = "login"
        wsConnected = false
        errorMsg = "登录已过期，请重新登录"
    }

    func refreshMe() async {
        do {
            let j = try await http("/api/me")
            if let u = j["user"] as? [String: Any], let c = asInt(u["coins"]) {
                await MainActor.run {
                    self.coins = c
                    if let uid = asInt(u["id"]) { self.userId = uid }
                }
            }
            if let r = asInt(j["relief"]), r > 0 {
                await MainActor.run {
                    self.reliefNotice = "🆘 破产救济 +\(r) 金币，明天继续努力！"
                }
            }
        } catch { }
    }

    @Published var myGames: [[String: Any]] = []
    func loadMyGames() async {
        do {
            let data = try await httpData("/api/me/games")
            if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                await MainActor.run { self.myGames = arr }
            }
        } catch { }
    }

    private func httpData(_ path: String) async throws -> Data {
        var base = serverURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path) else { throw NSError(domain: "url", code: -1) }
        var req = URLRequest(url: url)
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    // MARK: - WebSocket
    func connectWS() {
        guard let t = token else { return }
        manualClose = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        ws?.cancel()
        var base = serverURL.replacingOccurrences(of: "https://", with: "wss://")
        base = base.replacingOccurrences(of: "http://", with: "ws://")
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/ws") else { return }
        ws = URLSession.shared.webSocketTask(with: url)
        ws?.resume()
        listen()
        send(["t": "auth", "token": t], quiet: true)
    }

    func send(_ dict: [String: Any], quiet: Bool = false) {
        guard let ws = ws, ws.state == .running else {
            // 断网时点的按钮不能静默吞掉，给个提示
            if !quiet { errorMsg = "📡 网络连接中，请稍候再试" }
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(s)) { _ in }
    }

    private func listen() {
        let task = ws // 绑定当前连接，老连接的回调直接忽略
        task?.receive { [weak self] result in
            guard let self = self else { return }
            guard self.ws === task else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg {
                    DispatchQueue.main.async { self.applyMessage(text) }
                }
                self.listen()
            case .failure:
                DispatchQueue.main.async {
                    self.wsConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }

    /// 断线后 3 秒自动重连（用户主动退出则不）
    private func scheduleReconnect() {
        guard !manualClose, isLoggedIn else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isLoggedIn && !self.manualClose && !self.wsConnected {
                self.connectWS()
            }
        }
    }

    // MARK: - 消息处理（主线程）
    private func applyMessage(_ text: String) {
        guard let m = jsonDict(text), let t = m["t"] as? String else { return }
        switch t {
        case "hello":
            wsConnected = true
            // 重连成功，顺手清掉"网络连接中"这类提示
            if errorMsg?.contains("网络连接中") == true { errorMsg = nil }
            // 断线重连：自动重进房间（座位由服务端找回）
            if let rid = roomId, screen == "room" {
                send(["t": "room.join", "roomId": rid], quiet: true)
            }
        case "error":
            let msg = m["msg"] as? String ?? ""
            errorMsg = msg
            if msg.contains("房间不存在") { leaveRoom() }
            if msg.contains("登录失效") { handleAuthExpired() }
        case "room.state":
            roomId = m["roomId"] as? String
            gameKind = (m["game"] as? String) ?? "doudizhu"
            isFree = (m["free"] as? Bool) ?? false
            if let arr = m["seats"] as? [Any] {
                seats = arr.map { d in
                    if let d = d as? [String: Any] {
                        return SeatInfo(name: (d["name"] as? String) ?? "", kind: (d["kind"] as? String) ?? "")
                    } else {
                        return SeatInfo(name: "", kind: "empty")
                    }
                }
                // 自己的座位：按 userName 找（机器人重名不管；用户名唯一）
                if let i = seats.firstIndex(where: { $0.kind == "human" && $0.name == userName }) {
                    mySeat = i
                } else {
                    mySeat = -1
                }
            }
            if screen != "room" { screen = "room" }
        case "game.state":
            guard let st = m["state"] as? [String: Any] else { return }
            let g = m["game"] as? String
            if g == "texas" { applyTexasState(st) }
            else if g == "zha" { applyZhaState(st) }
            else { applyState(st) }
        case "game.over":
            let g = m["game"] as? String
            if g == "texas" { applyTexasOver(m); return }
            if g == "zha" { applyZhaOver(m); return }
            if let r = m["result"] as? [String: Any] {
                phase = "over"
                resultDeltas = (r["deltas"] as? [Any])?.compactMap(asInt) ?? []
                let win = (r["landlordWin"] as? Bool) ?? false
                let lw = (r["landlord"] as? Int) ?? -1
                let iWin = (win && lw == mySeat) || (!win && lw != mySeat)
                var s = iWin ? "🎉 你赢了" : "😅 输了"
                if (r["spring"] as? Bool) == true { s += "（春天!）" }
                if let b = asInt(r["bombCount"]), b > 0 { s += " 💣x\(b)" }
                resultInfo = s
            }
            Task { await refreshMe() }
        case "me":
            if let u = m["user"] as? [String: Any], let c = asInt(u["coins"]) { coins = c }
        case "room.chat":
            let from = m["from"] as? String ?? ""
            let text = m["text"] as? String ?? ""
            guard !text.isEmpty else { return }
            chatBubble = ChatBubble(from: from, text: text)
            // 4 秒后自动消失
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run { self?.chatBubble = nil }
            }
        case "game.hint":
            if let t = m["text"] as? String, !t.isEmpty {
                hintText = t
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    await MainActor.run { self?.hintText = nil }
                }
            } else {
                hintCards = (m["cards"] as? [Any])?.compactMap(asInt) ?? []
            }
        default:
            break
        }
    }

    private func applyState(_ st: [String: Any]) {
        phase = (st["phase"] as? String) ?? ""
        if let h = st["hand"] as? [Any] { hand = h.compactMap(asInt).map { Card(id: $0) } }
        if let hc = st["handCounts"] as? [Any] { handCounts = hc.compactMap(asInt) }
        landlord = asInt(st["landlord"]) ?? -1
        turn = asInt(st["turn"]) ?? -1
        bidTurn = asInt(st["bidTurn"]) ?? -1
        if let b = st["bids"] as? [Any] { bids = b.map { asInt($0) } }
        if let bo = st["bottom"] as? [Any] { bottom = bo.compactMap(asInt).map { Card(id: $0) } }
        if let lp = st["lastPlay"] as? [String: Any] {
            var p = LastPlay()
            p.seat = asInt(lp["seat"]) ?? -1
            if let cs = lp["cards"] as? [Any] { p.cards = cs.compactMap(asInt).map { Card(id: $0) } }
            if let info = lp["info"] as? [String: Any], let ty = info["type"] as? String {
                p.typeText = playTypeNames[ty] ?? ty
            }
            lastPlay = p
        } else {
            lastPlay = nil
        }
        if phase == "over" { /* 等 game.over 结算展示 */ }
    }

    // MARK: - 德州扑克
    private func applyTexasState(_ st: [String: Any]) {
        phase = (st["street"] as? String) ?? ""
        txStreet = phase
        if let b = st["board"] as? [Any] { txBoard = b.compactMap(asInt).map { Card(id: $0) } }
        if let h = st["hole"] as? [Any] { txHole = h.compactMap(asInt).map { Card(id: $0) } }
        if let s = st["stacks"] as? [Any] { txStacks = s.compactMap(asInt) }
        if let f = st["folded"] as? [Any] { txFolded = f.map { ($0 as? Bool) ?? false } }
        if let rb = st["roundBet"] as? [Any] { txRoundBet = rb.compactMap(asInt) }
        txPot = asInt(st["pot"]) ?? 0
        txToCall = asInt(st["toCall"]) ?? 0
        txMinRaiseTo = asInt(st["minRaiseTo"]) ?? 0
        txActor = asInt(st["actor"]) ?? -1
        txButton = asInt(st["button"]) ?? 0
        if let bl = st["blinds"] as? [String: Any] { txBB = asInt(bl["bb"]) ?? 0 }
        if let r = st["result"] as? [String: Any] { parseTexasResult(r) }
    }

    private func parseTexasResult(_ r: [String: Any]) {
        if let ws = r["winners"] as? [[String: Any]] {
            txWinners = ws.map { w in
                TexasWinner(seats: (w["seats"] as? [Any])?.compactMap(asInt) ?? [],
                            amount: asInt(w["amount"]) ?? 0,
                            showdown: (w["showdown"] as? Bool) ?? false)
            }
        } else {
            txWinners = []
        }
        txHandNames = (r["hands"] as? [Any])?.map { ($0 as? [String: Any])?["name"] as? String ?? "" } ?? []
        txHoleCards = (r["holeCards"] as? [Any])?.map { ($0 as? [Any])?.compactMap(asInt).map { Card(id: $0) } ?? [] } ?? []
    }

    private func applyTexasOver(_ m: [String: Any]) {
        phase = "over"
        txStreet = "over"
        if let r = m["result"] as? [String: Any] {
            parseTexasResult(r)
            resultDeltas = (r["deltas"] as? [Any])?.compactMap(asInt) ?? []
        }
        let my = mySeat < resultDeltas.count ? resultDeltas[mySeat] : 0
        if my > 0 { resultInfo = "🎉 你赢了 +\(my)" }
        else if my < 0 { resultInfo = "😅 输了 \(-my)" }
        else { resultInfo = "🤝 打平" }
        Task { await refreshMe() }
    }

    func txAct(_ type: String, amount: Int? = nil) {
        var a: [String: Any] = ["type": type]
        if let amount = amount { a["amount"] = amount }
        send(["t": "game.act", "action": a])
    }

    // MARK: - 炸金花
    private func applyZhaState(_ st: [String: Any]) {
        phase = (st["result"] is [String: Any]) ? "over" : "zha"
        if let h = st["hole"] as? [Any] { zhaHole = h.compactMap(asInt).map { Card(id: $0) } }
        if let l = st["looked"] as? [Any] { zhaLooked = l.map { ($0 as? Bool) ?? false } }
        if let f = st["folded"] as? [Any] { zhaFolded = f.map { ($0 as? Bool) ?? false } }
        if let s = st["stacks"] as? [Any] { zhaStacks = s.compactMap(asInt) }
        if let c = st["committed"] as? [Any] { zhaCommitted = c.compactMap(asInt) }
        zhaPot = asInt(st["pot"]) ?? 0
        zhaBetLevel = asInt(st["betLevel"]) ?? 1
        zhaCallAmount = asInt(st["callAmount"]) ?? 0
        zhaCompareCost = asInt(st["compareCost"]) ?? 0
        zhaActor = asInt(st["actor"]) ?? -1
        zhaButton = asInt(st["button"]) ?? 0
        zhaBase = asInt(st["base"]) ?? 0
    }

    private func applyZhaOver(_ m: [String: Any]) {
        phase = "over"
        guard let r = m["result"] as? [String: Any] else { return }
        resultDeltas = (r["deltas"] as? [Any])?.compactMap(asInt) ?? []
        zhaWinner = asInt(r["winner"]) ?? -1
        zhaShowdown = (r["showdown"] as? Bool) ?? false
        zhaHandNames = (r["hands"] as? [Any])?.map { ($0 as? String) ?? "" } ?? []
        let my = mySeat < resultDeltas.count ? resultDeltas[mySeat] : 0
        if my > 0 { resultInfo = "🎉 你赢了 +\(my)" }
        else if my < 0 { resultInfo = "😅 输了 \(-my)" }
        else { resultInfo = "🤝 打平" }
        Task { await refreshMe() }
    }

    func zhaAct(_ type: String, target: Int? = nil) {
        var a: [String: Any] = ["type": type]
        if let target = target { a["target"] = target }
        send(["t": "game.zha", "action": a])
    }

    /// 默认比牌目标：上家（存活）
    func zhaPrevAlive(_ seat: Int) -> Int {
        let n = zhaFolded.count
        guard n > 0 else { return -1 }
        for k in 1..<n {
            let s = (seat - k + n) % n
            if s < zhaFolded.count && !zhaFolded[s] { return s }
        }
        return -1
    }

    // MARK: - 改密码
    @MainActor
    func changePassword(old: String, new: String) async -> Bool {
        errorMsg = nil
        do {
            _ = try await http("/api/change-password", method: "POST",
                               body: ["oldPassword": old, "newPassword": new])
            return true
        } catch {
            errorMsg = error.localizedDescription
            return false
        }
    }

    // MARK: - 动作
    func createRoom(game: String = "doudizhu", seats: Int = 6) {
        if game == "texas" {
            send(["t": "room.create", "game": "texas", "seats": seats, "bots": seats - 1])
        } else if game == "zha" {
            send(["t": "room.create", "game": "zha", "seats": seats, "bots": seats - 1])
        } else {
            send(["t": "room.create", "bots": 2])
        }
    }
    /// 创建好友房：等齐人再手动开始
    func createFriendRoom(game: String, seats: Int, free: Bool = false) {
        var msg: [String: Any] = ["t": "room.create", "game": game, "seats": seats, "bots": 0, "waiting": true]
        if free { msg["free"] = true }
        send(msg)
    }
    func joinRoom(_ id: String) { send(["t": "room.join", "roomId": id]) }
    func leaveRoom() {
        send(["t": "room.leave"]); roomId = nil; screen = "lobby"; phase = ""
        gameKind = "doudizhu"; isFree = false; mySeat = -1
        txBoard = []; txHole = []; txWinners = []; txHandNames = []; txHoleCards = []
        zhaHole = []; zhaHandNames = []
        resultDeltas = []; resultInfo = ""
    }
    func startGame() { send(["t": "game.start"]) }
    func bid(_ score: Int) { send(["t": "game.bid", "score": score]) }
    func playCards(_ ids: [Int]) { send(["t": "game.play", "cards": ids]) }
    func pass() { send(["t": "game.pass"]) }
    func sendChat(_ text: String) { send(["t": "room.chat", "text": text]) }
    func requestHint() { hintCards = []; send(["t": "game.hint"]) }
}
