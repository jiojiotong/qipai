import SwiftUI

// MARK: - 设置（含改密码）
struct SettingsView: View {
    @EnvironmentObject var client: GameClient
    @State private var oldPw = ""
    @State private var newPw = ""
    @State private var newPw2 = ""
    @State private var doneMsg: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("设置").font(.title2).bold()
            Text("服务器地址").font(.footnote).foregroundColor(.gray)
            TextField("https://…/qipai", text: $client.serverURL)
                .textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
            Text("修改后重新登录生效").font(.footnote).foregroundColor(.gray)

            Divider()

            Text("修改密码").font(.headline)
            SecureField("旧密码", text: $oldPw).textFieldStyle(.roundedBorder)
            SecureField("新密码（至少4位）", text: $newPw).textFieldStyle(.roundedBorder)
            SecureField("确认新密码", text: $newPw2).textFieldStyle(.roundedBorder)
            if let e = client.errorMsg { Text(e).foregroundColor(.red).font(.footnote) }
            if let d = doneMsg { Text(d).foregroundColor(.green).font(.footnote) }
            Button("确认修改") {
                doneMsg = nil
                guard !oldPw.isEmpty, !newPw.isEmpty else { return }
                guard newPw == newPw2 else { client.errorMsg = "两次新密码不一致"; return }
                Task {
                    if await client.changePassword(old: oldPw, new: newPw) {
                        doneMsg = "密码修改成功"
                        oldPw = ""; newPw = ""; newPw2 = ""
                    }
                }
            }
            .buttonStyle(.borderedProminent).tint(gold).foregroundColor(.black)
            .disabled(oldPw.isEmpty || newPw.isEmpty || newPw2.isEmpty)
            Spacer()
        }
        .padding(24)
        .background(bgBlack)
    }
}
