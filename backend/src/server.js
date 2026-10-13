'use strict';
/** 棋牌后端：HTTP API + WebSocket 游戏 + 管理后台静态页 */
const path = require('path');
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const db = require('./db');
const { RoomManager } = require('./rooms');

const PORT = process.env.PORT || 3110;
const app = express();
app.use(express.json({ limit: '256kb' }));

// ---------- HTTP API ----------
function bearer(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}
function requireSession(req, res, next) {
  const u = db.getSessionUser(bearer(req));
  if (!u) return res.status(401).json({ error: '未登录' });
  req.user = u; next();
}
function requireAdmin(req, res, next) {
  const u = db.getSessionUser(bearer(req));
  if (!u || !u.is_admin) return res.status(403).json({ error: '需要管理员' });
  req.user = u; next();
}
const pub = u => ({ id: u.id, name: u.name, coins: u.coins, is_admin: !!u.is_admin });

app.get('/api/health', (req, res) => res.json({ ok: true, time: new Date().toISOString() }));

// 简单限流：防注册/登录暴力尝试（每 IP 每分钟 30 次）
const _rl = new Map();
function rateLimit(req, res, next) {
  const ip = req.headers['x-forwarded-for'] || req.headers['x-real-ip'] || req.socket.remoteAddress || '?';
  const now = Date.now();
  // 防止 Map 无限增长
  if (_rl.size > 2000) {
    for (const [k, v] of _rl) { if (!v.length || now - v[v.length - 1] > 60000) _rl.delete(k); }
  }
  const arr = (_rl.get(ip) || []).filter(t => now - t < 60000);
  arr.push(now);
  _rl.set(ip, arr);
  if (arr.length > 30) return res.status(429).json({ error: '操作太频繁，稍后再试' });
  next();
}
app.post('/api/register', rateLimit, (req, res) => {
  try {
    const u = db.createUser(req.body.name, req.body.password);
    const token = db.createSession(u.id);
    res.json({ token, user: pub(u) });
  } catch (e) { res.status(400).json({ error: e.message }); }
});
app.post('/api/login', rateLimit, (req, res) => {
  const u = db.verifyUser(req.body.name, req.body.password);
  if (!u) return res.status(400).json({ error: '用户名或密码错误' });
  const token = db.createSession(u.id);
  res.json({ token, user: pub(db.getUser(u.id)) });
});
app.post('/api/logout', requireSession, (req, res) => {
  const tok = bearer(req);
  db.destroySession(tok);
  closeConnsWhere(c => c.token === tok); // 同 token 的 WS 一起断开
  res.json({ ok: true });
});
app.get('/api/me', requireSession, (req, res) => {
  const relief = db.reliefIfBroke(req.user.id);
  const u = pub(db.getUser(req.user.id));
  res.json({ user: u, relief });
});
app.get('/api/me/games', requireSession, (req, res) => {
  res.json(db.myGames(req.user.id));
});
app.post('/api/change-password', requireSession, (req, res) => {
  try {
    const tok = bearer(req);
    db.changePassword(req.user.id, req.body.oldPassword, req.body.newPassword, tok);
    closeConnsWhere(c => c.userId === req.user.id && c.token !== tok); // 踢掉其他设备
    res.json({ ok: true });
  } catch (e) { res.status(400).json({ error: e.message }); }
});

// 管理后台 API
app.get('/api/admin/config', requireAdmin, (req, res) => res.json(db.getAllConfig()));
app.put('/api/admin/config', requireAdmin, (req, res) => {
  try {
    const allowed = ['base_score', 'start_coins', 'bot_delay_ms', 'room_max', 'texas_bb', 'zha_base', 'relief_coins'];
    if (!allowed.includes(req.body.key)) return res.status(400).json({ error: '不允许的配置项' });
    db.setConfig(req.body.key, req.body.value);
    res.json({ ok: true });
  } catch (e) { res.status(400).json({ error: e.message }); }
});
app.get('/api/admin/users', requireAdmin, (req, res) => res.json(db.listUsers()));
app.post('/api/admin/users/:id/coins', requireAdmin, (req, res) => {
  const uid = parseInt(req.params.id, 10);
  if (!Number.isInteger(uid) || !db.getUser(uid)) return res.status(404).json({ error: '用户不存在' });
  const delta = parseInt(req.body.delta, 10);
  if (!Number.isFinite(delta) || Math.abs(delta) > 1000000) return res.status(400).json({ error: '金额非法' });
  const coins = db.addCoins(uid, delta, req.body.reason || '管理员调整');
  res.json({ ok: true, coins });
});
app.get('/api/admin/games', requireAdmin, (req, res) => res.json(db.recentGames(50)));
app.get('/api/admin/rooms', requireAdmin, (req, res) => {
  let list = rooms.list();
  // ?search=R123 按房号模糊搜；?user=xxx 按用户ID或用户名找所在房间
  const q = (req.query.search || '').trim().toUpperCase();
  const u = (req.query.user || '').trim().toLowerCase();
  if (q) list = list.filter(r => r.roomId.toUpperCase().includes(q));
  if (u) list = list.filter(r => (r.players || []).some(p => p && (
    String(p.userId) === u || String(p.seat) === u || (p.name || '').toLowerCase().includes(u)
  )));
  res.json(list);
});
// 🎬 导演模式：指定某房间下一把谁赢（温和版，生效后自动清除）。seat=-1 取消
app.post('/api/admin/cheat', requireAdmin, (req, res) => {
  const room = rooms.get(req.body.roomId);
  if (!room) return res.status(404).json({ error: '房间不存在' });
  const seat = parseInt(req.body.seat, 10);
  if (isNaN(seat) || seat < -1 || seat >= room.seatCount) return res.status(400).json({ error: 'bad seat' });
  room.luckySeat = seat;
  res.json({ ok: true, roomId: room.id, cheat: seat });
});
// 删除用户（连带 sessions/ledger/game_members；不能删自己、不能删最后一个管理员）
app.delete('/api/admin/users/:id', requireAdmin, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (id === req.user.id) return res.status(400).json({ error: '不能删除自己' });
  try {
    if (!db.deleteUser(id)) return res.status(404).json({ error: '用户不存在' });
    // 把他从所有房间踢掉（座位变机器人代打，不断线死锁）
    for (const room of rooms.rooms.values()) {
      if (room.seatOfUser(id) !== -1) {
        room.removeHuman(id);
        room.onHumanLeft();
        rooms.hooks.broadcast(room.id, room.roomState());
      }
    }
    // 踢掉他的 WebSocket 连接
    for (const [ws, c] of conns.entries()) {
      if (c.userId === id) { try { ws.close(4000, '账号已删除'); } catch (_) {} }
    }
    res.json({ ok: true });
  } catch (e) { res.status(400).json({ error: e.message }); }
});
// 删除单局对局（连带 game_members）
app.delete('/api/admin/games/:id', requireAdmin, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!db.deleteGame(id)) return res.status(404).json({ error: '对局不存在' });
  res.json({ ok: true });
});

app.use('/admin', express.static(path.join(__dirname, '..', 'web')));

// ---------- WebSocket ----------
const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws', maxPayload: 64 * 1024 });
const conns = new Map(); // ws -> {userId, user, roomId}

const GAME_NAMES = { doudizhu: '斗地主', texas: '德州扑克', zha: '炸金花' };
const rooms = new RoomManager({
  config: (k) => db.getConfig(k),
  coinsOf: (userId) => { const u = db.getUser(userId); return u ? u.coins : 0; },
  send: (roomId, seatIdx, msg) => {
    for (const [ws, c] of conns) {
      const room = rooms.get(roomId);
      if (c.roomId === roomId && room && room.seats[seatIdx] && room.seats[seatIdx].kind === 'human' && room.seats[seatIdx].userId === c.userId) {
        if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
      }
    }
  },
  broadcast: (roomId, msg) => {
    const s = JSON.stringify(msg);
    for (const [ws, c] of conns) {
      if (c.roomId === roomId && ws.readyState === WebSocket.OPEN) ws.send(s);
    }
  },
  onGameOver: (room, result, players) => {
    const gname = GAME_NAMES[room.game] || room.game;
    if (!room.free) {
      for (const p of players) {
        if (p.kind === 'human' && p.delta !== 0) db.addCoins(p.userId, p.delta, `${gname}结算 ${room.id}`);
      }
    }
    db.saveGame(room.game, room.id, players, result, room.free ? 'free' : 'coins');
  },
});

function sendErr(ws, msg) { ws.send(JSON.stringify({ t: 'error', msg })); }

/** 快捷聊天预设短语（白名单，防乱发） */
const CHAT_PHRASES = [
  '大家好，很高兴见到各位',
  '快点吧，我等到花儿都谢了',
  '哈哈，运气真好',
  '哎呀，打错了',
  '你太厉害了',
  '再来一局',
  '谢谢',
  '承让承让',
];

/** 按条件关闭 WS 连接（会话失效时用） */
function closeConnsWhere(pred) {
  for (const [ws, c] of conns) {
    if (pred(c)) { try { ws.close(); } catch (_) {} }
  }
}

wss.on('connection', (ws) => {
  conns.set(ws, { userId: 0, user: null, roomId: null });
  const authTimer = setTimeout(() => { if (!conns.get(ws).userId) ws.close(); }, 8000);
  // 防 WS 洪水：5 秒内超 200 条消息直接断开
  let msgTimes = [];

  ws.on('message', (raw) => {
    const now = Date.now();
    msgTimes = msgTimes.filter(t => now - t < 5000);
    msgTimes.push(now);
    if (msgTimes.length > 200) { try { ws.close(); } catch (_) {} return; }
    let msg;
    try { msg = JSON.parse(raw); } catch { return sendErr(ws, '消息格式错误'); }
    const c = conns.get(ws);
    try {
      if (msg.t === 'auth') {
        const u = db.getSessionUser(msg.token);
        if (!u) return sendErr(ws, '登录失效');
        c.userId = u.id; c.user = u; c.token = msg.token;
        clearTimeout(authTimer);
        return ws.send(JSON.stringify({ t: 'hello', user: pub(u) }));
      }
      if (!c.userId) return sendErr(ws, '请先 auth');
      handleMsg(ws, c, msg);
    } catch (e) { sendErr(ws, e.message); }
  });

  ws.on('close', () => {
    const c = conns.get(ws);
    if (c && c.roomId) {
      const room = rooms.get(c.roomId);
      if (room) {
        room.removeHuman(c.userId);
        room.onHumanLeft(); // 轮到机器人则启动定时器，防断线死锁
        rooms.hooks.broadcast(c.roomId, room.roomState());
        // 房里没真人了 5 分钟后回收（给断线重连留窗口）
        if (!room.seats.some(s => s && s.kind === 'human')) {
          room.scheduleDestroy(() => rooms.remove(c.roomId));
        }
      }
    }
    conns.delete(ws);
  });
});

function handleMsg(ws, c, msg) {
  const me = db.getUser(c.userId); // 刷新金币等
  if (msg.t === 'room.list') {
    return ws.send(JSON.stringify({ t: 'room.list', rooms: rooms.list() }));
  }
  if (msg.t === 'room.create') {
    if (!me) throw new Error('用户不存在');
    // 先退出之前的房间（否则旧房间留幽灵座位）
    if (c.roomId) {
      const prev = rooms.get(c.roomId);
      if (prev) { prev.removeHuman(c.userId); prev.onHumanLeft(); rooms.hooks.broadcast(c.roomId, prev.roomState()); }
    }
    const room = rooms.create(me, {
      bots: msg.bots !== undefined ? msg.bots : 2,
      game: msg.game,
      seats: msg.seats,
      bb: msg.bb,
      base: msg.base,
      free: !!msg.free,
    });
    c.roomId = room.id;
    ws.send(JSON.stringify(room.roomState())); // 先发房间状态（客户端先知道自己的座位）
    if (!msg.waiting) room.start(); // 好友房等齐人再手动开始（再发各座位牌桌状态）
    return;
  }
  if (msg.t === 'room.join') {
    if (!me) throw new Error('用户不存在');
    const room = rooms.get(msg.roomId);
    if (!room) throw new Error('房间不存在');
    room.cancelDestroy(); // 重连回来，取消回收倒计时
    if (c.roomId && c.roomId !== room.id) {
      const prev = rooms.get(c.roomId);
      if (prev) { prev.removeHuman(c.userId); prev.onHumanLeft(); rooms.hooks.broadcast(c.roomId, prev.roomState()); }
    }
    c.roomId = room.id;
    const seat = room.addHuman(me);
    room.onHumanLeft(); // addHuman 清掉了旧机器人定时器，这里重新评估（仍是机器人轮则重排）
    rooms.hooks.broadcast(room.id, room.roomState());
    const gs = room.gameStateFor(seat);
    if (gs) ws.send(JSON.stringify({ t: 'game.state', game: gs.game, state: gs.state }));
    return;
  }
  if (msg.t === 'room.leave') {
    const room = rooms.get(c.roomId);
    if (room) {
      room.removeHuman(c.userId);
      room.onHumanLeft();
      rooms.hooks.broadcast(room.id, room.roomState());
      if (!room.seats.some(s => s && s.kind === 'human')) rooms.remove(room.id);
    }
    c.roomId = null;
    return ws.send(JSON.stringify({ t: 'ok' }));
  }
  if (msg.t === 'game.start') {
    const room = rooms.get(c.roomId);
    if (!room) throw new Error('不在房间里');
    if (room.isPlaying()) throw new Error('对局进行中');
    room.start();
    return;
  }
  if (msg.t === 'room.chat') {
    const room = rooms.get(c.roomId);
    if (!room) throw new Error('不在房间里');
    const text = String(msg.text || '');
    if (!CHAT_PHRASES.includes(text)) throw new Error('只能发送预设短语');
    const now = Date.now();
    if (c.lastChat && now - c.lastChat < 5000) throw new Error('发言太快了，歇5秒');
    c.lastChat = now;
    rooms.hooks.broadcast(room.id, { t: 'room.chat', from: me.name, text });
    return;
  }
  if (msg.t === 'game.hint') {
    const room = rooms.get(c.roomId);
    if (!room) throw new Error('不在房间里');
    const h = room.hintFor(c.userId);
    if (!h) throw new Error('现在不能提示');
    ws.send(JSON.stringify({ t: 'game.hint', ...h }));
    return;
  }
  if (['game.bid', 'game.play', 'game.pass', 'game.act', 'game.zha'].includes(msg.t)) {
    const room = rooms.get(c.roomId);
    if (!room) throw new Error('不在房间里');
    room.humanAction(c.userId, msg);
    // 动作后给自己补一份最新金币（结算时变的）
    ws.send(JSON.stringify({ t: 'me', user: pub(db.getUser(c.userId)) }));
    return;
  }
  throw new Error('未知消息');
}

server.listen(PORT, '127.0.0.1', () => {
  console.log(`qipai-server listening on 127.0.0.1:${PORT}`);
});
