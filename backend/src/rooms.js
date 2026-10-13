'use strict';
/**
 * 房间与对局调度。真人走 WS，空位用机器人补齐。
 * 纯调度逻辑，通过 hooks 与 server.js 解耦：
 *   hooks.send(seatIdx, msg)      发给某座位（仅真人）
 *   hooks.broadcast(msg)          发给房间内所有真人
 *   hooks.onGameOver(room, result) 结算回调（记账本/存对局）
 *   hooks.coinsOf(userId)         查真人金币
 */
const { DoudizhuGame } = require('./games/doudizhu');
const { chooseBid, choosePlay } = require('./games/doudizhu_bot');
const { TexasGame } = require('./games/texas');
const { decide: texasDecide } = require('./games/texas_bot');
const { ZhaGame } = require('./games/zha');
const { decide: zhaDecide } = require('./games/zha_bot');

let seq = 0;

class Room {
  constructor(id, opts, hooks) {
    this.id = id;
    this.hooks = hooks;
    this.seatCount = opts.seats || 3;
    this.seats = new Array(this.seatCount).fill(null); // {kind:'human'|'bot', userId, name}
    this.botTimer = null;
    this.createdAt = Date.now();
    this.bots = opts.bots !== undefined ? opts.bots : 2;
    this.game = '?';
    this.free = !!opts.free; // 记分模式：不输赢金币，只记分
    this.luckySeat = -1; // 导演模式目标座位（管理后台指定），-1=关闭；一次性，生效后清除
  }

  seatOfUser(userId) { return this.seats.findIndex(s => s && s.kind === 'human' && s.userId === userId); }

  addHuman(user) {
    if (this.seatOfUser(user.id) !== -1) return this.seatOfUser(user.id);
    // 断线重连：优先找回自己的旧座位
    let idx = this.seats.findIndex(s => s && s.kind === 'bot' && s.wasUserId === user.id);
    if (idx === -1) idx = this.seats.findIndex(s => s && s.kind === 'bot' && !s.wasUserId);
    if (idx === -1) idx = this.seats.findIndex(s => !s);
    if (idx === -1) idx = this.seats.findIndex(s => s && s.kind === 'bot');
    if (idx === -1) throw new Error('房间已满');
    this.seats[idx] = { kind: 'human', userId: user.id, name: user.name };
    this._clearBotTimer(); // 人回来了，之前排期的机器人代打作废
    return idx;
  }

  removeHuman(userId) {
    const i = this.seatOfUser(userId);
    if (i !== -1) this.seats[i] = { kind: 'bot', userId: 0, name: '机器人', wasUserId: userId };
  }

  /** 真人离开后调用：若轮到机器人行动则启动定时器（防断线死锁） */
  onHumanLeft() {}

  /** 出牌提示：返回建议出的牌 id 数组；不支持返回 null */
  hintFor(/* userId */) { return null; }

  fillBots() {
    for (let i = 0; i < this.seatCount; i++) {
      if (!this.seats[i]) this.seats[i] = { kind: 'bot', userId: 0, name: '机器人' };
    }
  }

  botDelay() { return parseInt(this.hooks.config('bot_delay_ms') || '900', 10); }

  _clearBotTimer() { if (this.botTimer) { clearTimeout(this.botTimer); this.botTimer = null; } }
  destroy() { this._clearBotTimer(); this.cancelDestroy(); }
  /** 没真人时 5 分钟后回收（给断线重连留窗口） */
  scheduleDestroy(fn, ms = 5 * 60 * 1000) {
    this.cancelDestroy();
    this.destroyTimer = setTimeout(() => { this.destroyTimer = null; fn(); }, ms);
  }
  cancelDestroy() { if (this.destroyTimer) { clearTimeout(this.destroyTimer); this.destroyTimer = null; } }

  isPlaying() { return false; }
  gameStateFor(/* seat */) { return null; }

  roomState() {
    return {
      t: 'room.state', roomId: this.id, game: this.game,
      seats: this.seats.map(s => s ? { kind: s.kind, name: s.name } : null),
      playing: this.isPlaying(),
      free: this.free,
    };
  }
}

// ---------------- 斗地主 ----------------
class DoudizhuRoom extends Room {
  constructor(id, opts, hooks) {
    super(id, { ...opts, seats: 3 }, hooks);
    this.game = 'doudizhu';
    this.ddz = null;
    this.bidStarter = 0; // 首叫轮换，公平
  }

  isPlaying() { return !!this.ddz && this.ddz.phase !== 'over'; }
  gameStateFor(seat) {
    if (!this.isPlaying()) return null;
    return { game: 'doudizhu', state: this.ddz.getState(seat) };
  }

  start() {
    this.fillBots();
    const baseScore = parseInt(this.hooks.config('base_score') || '100', 10);
    // 准入：金币须覆盖地主最坏情况（输 2 家 × 封顶 32 倍），防止输成负数
    const minCoins = baseScore * 64;
    for (const s of this.seats) {
      if (!this.free && s.kind === 'human' && this.hooks.coinsOf(s.userId) < minCoins) {
        throw new Error(`${s.name} 金币不足（需 ${minCoins}）`);
      }
    }
    const seatIds = this.seats.map((s, i) => s.kind === 'bot' ? `bot:${this.id}:${i}` : `user:${s.userId}`);
    this.ddz = new DoudizhuGame(seatIds, { baseScore, bidStarter: this.bidStarter });
    this.bidStarter = (this.bidStarter + 1) % 3; // 下局轮换
    if (this.luckySeat >= 0) { this.ddz.rigFor(this.luckySeat); this.luckySeat = -1; } // 导演模式：一次性，下把生效后清除
    this._pushStates();
    this._pumpBot();
  }

  _pushStates() {
    this.seats.forEach((s, i) => {
      if (s.kind === 'human') this.hooks.send(i, { t: 'game.state', game: 'doudizhu', state: this.ddz.getState(i) });
    });
    for (const e of this.ddz.drainEvents()) this.hooks.broadcast({ t: 'game.event', event: e });
  }

  _pumpBot() {
    this._clearBotTimer();
    if (!this.isPlaying()) return;
    const g = this.ddz;
    const seat = g.phase === 'bid' ? g.bidTurn : g.turn;
    if (this.seats[seat].kind !== 'bot') return;
    this.botTimer = setTimeout(() => {
      this.botTimer = null;
      try {
        if (g.phase === 'bid') {
          g.bid(seat, chooseBid(g.hands[seat], g.bidMax));
        } else {
          const last = g.lastPlay;
          const mv = choosePlay(g.hands[seat], last ? last.info : null,
            { seat, landlord: g.landlord, lastSeat: last ? last.seat : -1 });
          if (mv) g.play(seat, mv.cards);
          else g.pass(seat);
        }
      } catch (e) {
        try { if (g.phase === 'play' && g.turn === seat && g.lastPlay) g.pass(seat); } catch (_) {}
      }
      this._pushStates();
      if (g.phase === 'over') this._finish();
      else this._pumpBot();
    }, this.botDelay());
  }

  humanAction(userId, msg) {
    const seat = this.seatOfUser(userId);
    if (seat === -1) throw new Error('你不在房间里');
    const g = this.ddz;
    if (!this.isPlaying()) throw new Error('对局未开始');
    if (msg.t === 'game.bid') g.bid(seat, msg.score);
    else if (msg.t === 'game.play') g.play(seat, msg.cards);
    else if (msg.t === 'game.pass') g.pass(seat);
    else throw new Error('未知动作');
    this._pushStates();
    if (g.phase === 'over') this._finish();
    else this._pumpBot();
  }

  onHumanLeft() { this._pumpBot(); }

  hintFor(userId) {
    const seat = this.seatOfUser(userId);
    const g = this.ddz;
    if (seat === -1 || !this.isPlaying() || g.phase !== 'play' || g.turn !== seat) return null;
    const last = g.lastPlay;
    const mv = choosePlay(g.hands[seat], last ? last.info : null,
      { seat, landlord: g.landlord, lastSeat: last ? last.seat : -1 });
    return { cards: mv ? mv.cards : [] }; // 空数组 = 建议不出
  }

  _finish() {
    this._clearBotTimer();
    const result = this.ddz.result;
    const players = this.seats.map((s, i) => ({
      kind: s.kind, name: s.name,
      userId: s.kind === 'human' ? s.userId : 0,
      delta: result.deltas[i],
    }));
    this.hooks.onGameOver(this, result, players);
    this.hooks.broadcast({ t: 'game.over', game: 'doudizhu', result, players: players.map(p => ({ name: p.name, delta: p.delta })) });
    this.ddz = null;
    this.hooks.broadcast(this.roomState());
  }
}

// ---------------- 德州扑克 ----------------
class TexasRoom extends Room {
  constructor(id, opts, hooks) {
    const seats = Math.min(9, Math.max(2, parseInt(opts.seats, 10) || 6));
    super(id, { ...opts, seats }, hooks);
    this.game = 'texas';
    this.g = null;
    this.button = 0;
    this.bb = Math.max(2, parseInt(opts.bb, 10) || parseInt(hooks.config('texas_bb') || '10', 10));
    this.buyIn = parseInt(opts.buyIn, 10) || this.bb * 100;
  }

  isPlaying() { return !!this.g && !this.g.result; }
  gameStateFor(seat) {
    if (!this.isPlaying()) return null;
    return { game: 'texas', state: this.g.getState(seat) };
  }

  start() {
    this.fillBots();
    // 真人金币须覆盖买入
    for (const s of this.seats) {
      if (!this.free && s.kind === 'human' && this.hooks.coinsOf(s.userId) < this.buyIn) {
        throw new Error(`${s.name} 金币不足（需 ${this.buyIn}）`);
      }
    }
    const seatIds = this.seats.map((s, i) => s.kind === 'bot' ? `bot:${this.id}:${i}` : `user:${s.userId}`);
    this.g = new TexasGame(seatIds, {
      smallBlind: Math.max(1, Math.floor(this.bb / 2)),
      bigBlind: this.bb,
      buyIn: this.buyIn,
      button: this.button,
    });
    this.button = (this.button + 1) % this.seatCount; // 下局轮换
    if (this.luckySeat >= 0) { this.g.rigFor(this.luckySeat); this.luckySeat = -1; } // 导演模式：一次性
    this._pushStates();
    this._pumpBot();
  }

  _pushStates() {
    this.seats.forEach((s, i) => {
      if (s.kind === 'human') this.hooks.send(i, { t: 'game.state', game: 'texas', state: this.g.getState(i) });
    });
    for (const e of this.g.drainEvents()) this.hooks.broadcast({ t: 'game.event', game: 'texas', event: e });
  }

  _pumpBot() {
    this._clearBotTimer();
    if (!this.isPlaying()) return;
    const g = this.g;
    const seat = g.actor;
    if (seat === -1 || this.seats[seat].kind !== 'bot') return;
    this.botTimer = setTimeout(() => {
      this.botTimer = null;
      try {
        g.act(seat, texasDecide(g, seat));
      } catch (e) {
        // 机器人不应出错；出错则弃牌保推进
        try { if (!g.result && g.actor === seat) g.act(seat, { type: 'fold' }); } catch (_) {}
      }
      this._pushStates();
      if (g.result) this._finish();
      else this._pumpBot();
    }, this.botDelay());
  }

  humanAction(userId, msg) {
    const seat = this.seatOfUser(userId);
    if (seat === -1) throw new Error('你不在房间里');
    const g = this.g;
    if (!this.isPlaying()) throw new Error('对局未开始');
    if (msg.t !== 'game.act') throw new Error('未知动作');
    g.act(seat, msg.action || {});
    this._pushStates();
    if (g.result) this._finish();
    else this._pumpBot();
  }

  onHumanLeft() { this._pumpBot(); }

  hintFor(userId) {
    const seat = this.seatOfUser(userId);
    const g = this.g;
    if (seat === -1 || !this.isPlaying() || g.actor !== seat) return null;
    const a = texasDecide(g, seat);
    const label = { fold: '弃牌', check: '过牌', call: '跟注', raise: '加注' }[a.type] || a.type;
    let extra = '';
    if (a.type === 'call') extra = ' ' + g.toCall(seat);
    if (a.type === 'raise' && a.amount) extra = '到 ' + a.amount;
    return { text: '建议：' + label + extra };
  }

  _finish() {
    this._clearBotTimer();
    const result = this.g.result;
    const players = this.seats.map((s, i) => ({
      kind: s.kind, name: s.name,
      userId: s.kind === 'human' ? s.userId : 0,
      delta: result.deltas[i],
    }));
    this.hooks.onGameOver(this, result, players);
    this.hooks.broadcast({ t: 'game.over', game: 'texas', result, players: players.map(p => ({ name: p.name, delta: p.delta })) });
    this.g = null;
    this.hooks.broadcast(this.roomState());
  }
}

// ---------------- 炸金花 ----------------
class ZhaRoom extends Room {
  constructor(id, opts, hooks) {
    const seats = Math.min(8, Math.max(2, parseInt(opts.seats, 10) || 5));
    super(id, { ...opts, seats }, hooks);
    this.game = 'zha';
    this.g = null;
    this.base = Math.max(1, parseInt(opts.base, 10) || parseInt(hooks.config('zha_base') || '10', 10));
    this.buyIn = parseInt(opts.buyIn, 10) || this.base * 500;
    this.button = 0; // 庄家轮换，公平
  }

  isPlaying() { return !!this.g && !this.g.result; }
  gameStateFor(seat) {
    if (!this.isPlaying()) return null;
    return { game: 'zha', state: this.g.getState(seat) };
  }

  start() {
    this.fillBots();
    for (const s of this.seats) {
      if (!this.free && s.kind === 'human' && this.hooks.coinsOf(s.userId) < this.buyIn) {
        throw new Error(`${s.name} 金币不足（需 ${this.buyIn}）`);
      }
    }
    const seatIds = this.seats.map((s, i) => s.kind === 'bot' ? `bot:${this.id}:${i}` : `user:${s.userId}`);
    this.g = new ZhaGame(seatIds, { baseBet: this.base, buyIn: this.buyIn, button: this.button });
    this.button = (this.button + 1) % this.seatCount; // 下局轮换
    if (this.luckySeat >= 0) { this.g.rigFor(this.luckySeat); this.luckySeat = -1; } // 导演模式：一次性
    this._pushStates();
    this._pumpBot();
  }

  _pushStates() {
    this.seats.forEach((s, i) => {
      if (s.kind === 'human') this.hooks.send(i, { t: 'game.state', game: 'zha', state: this.g.getState(i) });
    });
    for (const e of this.g.drainEvents()) this.hooks.broadcast({ t: 'game.event', game: 'zha', event: e });
  }

  _pumpBot() {
    this._clearBotTimer();
    if (!this.isPlaying()) return;
    const g = this.g;
    const seat = g.actor;
    if (seat === -1 || this.seats[seat].kind !== 'bot') return;
    this.botTimer = setTimeout(() => {
      this.botTimer = null;
      try {
        g.act(seat, zhaDecide(g, seat));
      } catch (e) {
        try { if (!g.result && g.actor === seat) g.act(seat, { type: 'fold' }); } catch (_) {}
      }
      this._pushStates();
      if (g.result) this._finish();
      else this._pumpBot();
    }, this.botDelay());
  }

  humanAction(userId, msg) {
    const seat = this.seatOfUser(userId);
    if (seat === -1) throw new Error('你不在房间里');
    const g = this.g;
    if (!this.isPlaying()) throw new Error('对局未开始');
    if (msg.t !== 'game.zha') throw new Error('未知动作');
    g.act(seat, msg.action || {});
    this._pushStates();
    if (g.result) this._finish();
    else this._pumpBot();
  }

  onHumanLeft() { this._pumpBot(); }

  hintFor(userId) {
    const seat = this.seatOfUser(userId);
    const g = this.g;
    if (seat === -1 || !this.isPlaying() || g.actor !== seat) return null;
    const a = zhaDecide(g, seat);
    const labels = { look: '看牌', fold: '弃牌', call: '跟注', raise: '加注', compare: '比牌' };
    let text = '建议：' + (labels[a.type] || a.type);
    if (a.type === 'compare') {
      const t = g._prevAlive(seat);
      const nm = t !== -1 && this.seats[t] ? this.seats[t].name : '';
      if (nm) text += '（' + nm + '）';
    }
    return { text };
  }

  _finish() {
    this._clearBotTimer();
    const result = this.g.result;
    const players = this.seats.map((s, i) => ({
      kind: s.kind, name: s.name,
      userId: s.kind === 'human' ? s.userId : 0,
      delta: result.deltas[i],
    }));
    this.hooks.onGameOver(this, result, players);
    this.hooks.broadcast({ t: 'game.over', game: 'zha', result, players: players.map(p => ({ name: p.name, delta: p.delta })) });
    this.g = null;
    this.hooks.broadcast(this.roomState());
  }
}

class RoomManager {
  constructor(hooks) { this.rooms = new Map(); this.hooks = hooks; }

  create(ownerUser, opts = {}) {
    const max = parseInt(this.hooks.config('room_max') || '20', 10);
    if (this.rooms.size >= max) throw new Error('房间数已达上限');
    const id = 'R' + (++seq).toString(36).toUpperCase() + Date.now().toString(36).slice(-4).toUpperCase();
    const game = opts.game === 'texas' ? 'texas' : opts.game === 'zha' ? 'zha' : 'doudizhu';
    const room = game === 'texas'
      ? new TexasRoom(id, opts, this._roomHooks(id))
      : game === 'zha'
        ? new ZhaRoom(id, opts, this._roomHooks(id))
        : new DoudizhuRoom(id, opts, this._roomHooks(id));
    room.addHuman(ownerUser);
    this.rooms.set(id, room);
    return room;
  }

  _roomHooks(id) {
    const base = this.hooks;
    return {
      config: base.config,
      send: (seatIdx, msg) => base.send(id, seatIdx, msg),
      broadcast: (msg) => base.broadcast(id, msg),
      onGameOver: base.onGameOver,
      coinsOf: base.coinsOf,
    };
  }

  get(id) { return this.rooms.get(id) || null; }
  list() {
    return [...this.rooms.values()].map(r => ({
      roomId: r.id, game: r.game,
      seats: r.seats.filter(Boolean).length,
      seatCount: r.seatCount, playing: r.isPlaying(), free: r.free,
      // 导演模式用：座位名单 + 当前指定的下把赢家（仅管理后台可见，含 userId）
      players: r.seats.map((s, i) => s ? { seat: i, name: s.name, kind: s.kind, userId: s.kind === 'human' ? s.userId : 0 } : null),
      cheat: r.luckySeat,
    }));
  }
  remove(id) { const r = this.rooms.get(id); if (r) { r.destroy(); this.rooms.delete(id); } }
}

module.exports = { Room, DoudizhuRoom, TexasRoom, ZhaRoom, RoomManager };
