import SwiftUI
import Foundation

// MARK: - 我的战绩
struct MyGamesView: View {
    @EnvironmentObject var client: GameClient
    @State private var selected: [String: Any]? = nil
    @State private var showDetail = false
    let gameNames = ["doudizhu": "🃏 斗地主", "texas": "🎰 德州扑克", "zha": "🤑 炸金花"]

    var body: some View {
        VStack(spacing: 0) {
            Text("📊 我的战绩").font(.title2).bold().padding()
            if client.myGames.isEmpty {
                Text("还没有对局记录，去打一局吧！").foregroundColor(.gray).padding()
                Spacer()
            } else {
                List {
                    ForEach(0..<client.myGames.count, id: \.self) { i in
                        let g = client.myGames[i]
                        let game = g["game"] as? String ?? ""
                        let delta = asInt(g["delta"]) ?? 0
                        let time = (g["created_at"] as? String) ?? ""
                        let isFree = (g["mode"] as? String) == "free"
                        Button {
                            selected = g
                            showDetail = true
                        } label: {
                            HStack {
                                Text((gameNames[game] ?? game) + (isFree ? " 📝" : "")).font(.subheadline).foregroundColor(.white)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(delta >= 0 ? "+" : "")\(delta)")
                                        .bold().foregroundColor(delta >= 0 ? .green : .red)
                                    Text(time).font(.caption2).foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(bgBlack)
        .task { await client.loadMyGames() }
        .sheet(isPresented: $showDetail) {
            if let g = selected {
                GameDetailView(game: g, gameNames: gameNames)
            }
        }
    }
}

struct GameDetailView: View {
    let game: [String: Any]
    let gameNames: [String: String]

    var players: [(name: String, delta: Int)] {
        guard let ps = game["players"] as? String,
              let data = ps.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return arr.map { (name: ($0["name"] as? String) ?? "?", delta: asInt($0["delta"]) ?? 0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(gameNames[game["game"] as? String ?? ""] ?? "对局").font(.title2).bold()
            Text((game["created_at"] as? String) ?? "").font(.footnote).foregroundColor(.gray)
            if players.isEmpty {
                Text("暂无详细数据").foregroundColor(.gray)
            } else {
                ForEach(0..<players.count, id: \.self) { i in
                    let p = players[i]
                    HStack {
                        Text(p.name).font(.subheadline)
                        Spacer()
                        Text("\(p.delta >= 0 ? "+" : "")\(p.delta)")
                            .bold().foregroundColor(p.delta >= 0 ? .green : .red)
                    }
                    .padding(.horizontal)
                }
            }
            Spacer()
        }
        .padding()
        .background(bgBlack)
    }
}
