'use strict';
/**
 * 炸金花引擎（纯逻辑，无 I/O）
 * 单局买入制：每手每人 fresh buyIn 筹码，单局零和结算。
 *
 * 规则（常见朋友局）：
 * - 底注 baseBet，人手 3 张暗牌
 * - 未看牌（闷）：下注 1 倍；看牌后：下注 2 倍
 * - 行动：看牌 / 弃牌 / 跟注 / 加注（注额+1 档）/ 比牌（付 2 倍当前注，与上家比；平局发起者输）
 * - 牌型：豹子 > 同花顺 > 同花 > 顺子 > 对子 > 单张；235 专杀豹子（可配置）
 * - 超过 maxRounds 轮无人获胜则强制亮牌比大小
 */
const { rank, suit, cardStr, newDeck52, mulberry32 } = require('./cards');

const CAT_NAMES = ['单张', '对子', '顺子', '同花', '同花顺', '豹子'];

/** 3 张牌评分 → {cat, tb} */
function eval3(cards) {
  const rs = cards.map(rank).sort((a, b) => b - a);
  const flush = cards.every(c => suit(c) === suit(cards[0]));
  const uniq = [...new Set(rs)];
  let straightHigh = 0;
  if (uniq.length === 3) {
    if (uniq[0] - uniq[2] === 2) straightHigh = uniq[0];
    else if (uniq[0] === 15 && uniq[1] === 14 && uniq[2] === 3) straightHigh = 3; // A23 最小顺子（2=r15）
    else if (uniq[0] === 15) {
      // 2 参与的顺子（如 234）：把 2(r15) 当低牌 2 看是否连续
      const low = uniq.map(r => r === 15 ? 2 : r).sort((a, b) => b - a);
      if (low[0] - low[2] === 2) straightHigh = low[0];
    }
  }
  if (uniq.length === 1) return { cat: 5, tb: [uniq[0]] };                       // 豹子
  if (flush && straightHigh) return { cat: 4, tb: [straightHigh] };              // 同花顺
  if (flush) return { cat: 3, tb: rs };                                         // 同花
  if (straightHigh) return { cat: 2, tb: [straightHigh] };                      // 顺子
  if (uniq.length === 2) {                                                      // 对子
    const p = rs[0] === rs[1] ? rs[0] : rs[1];
    const k = rs.find(r => r !== p);
    return { cat: 1, tb: [p, k] };
  }
  return { cat: 0, tb: rs };                                                    // 单张
}

function cmpScore(a, b) {
  if (a.cat !== b.cat) return a.cat - b.cat;
  for (let i = 0; i < Math.max(a.tb.length, b.tb.length); i++) {
    const d = (a.tb[i] || 0) - (b.tb[i] || 0);
    if (d !== 0) return d;
  }
  return 0;
}

function is235(score) {
  // 235 专杀豹子：2(r15) 3(r3) 5(r5)，tb 降序为 [15,5,3]
  return score.cat === 0 && score.tb[0] === 15 && score.tb[1] === 5 && score.tb[2] === 3;
}

/** 比牌：返回 1(a胜) / -1(b胜) / 0(平) */
function compare3(aCards, bCards, allow235 = true) {
  const sa = eval3(aCards), sb = eval3(bCards);
  if (allow235) {
    const a235 = is235(sa), b235 = is235(sb);
    if (sa.cat === 5 && b235) return -1;  // 235 杀豹子
    if (sb.cat === 5 && a235) return 1;
    if (a235 || b235) { /* 235 对其他牌就是最烂单张，正常比 */ }
  }
  const c = cmpScore(sa, sb);
  return c > 0 ? 1 : c < 0 ? -1 : 0;
}

function handName(score) { return CAT_NAMES[score.cat]; }

class ZhaGame {
  /**
   * @param {string[]} seatIds 2..8 个座位
   * @param {object} opts {baseBet, buyIn, seed, maxRounds, allow235, maxLevel}
   */
  constructor(seatIds, opts = {}) {
    if (seatIds.length < 2 || seatIds.length > 8) throw new Error('人数 2..8');
    this.seatIds = [...seatIds];
    this.n = seatIds.length;
    this.base = opts.baseBet || 10;
    this.buyIn = opts.buyIn || this.base * 500;
    this.maxRounds = opts.maxRounds || 15;
    this.allow235 = opts.allow235 !== false;
    this.maxLevel = opts.maxLevel || 10;
    this.button = opts.button || 0; // 庄家，轮换
    this.rng = opts.seed !== undefined ? mulberry32(opts.seed) : Math.random;
    this.events = [];
    this._newHand();
  }

  _newHand() {
    const deck = newDeck52(this.rng);
    this.hole = [];
    for (let i = 0; i < this.n; i++) this.hole.push([deck.pop(), deck.pop(), deck.pop()]);
    this.stacks = new Array(this.n).fill(this.buyIn);
    this.committed = new Array(this.n).fill(0);
    this.folded = new Array(this.n).fill(false);
    this.looked = new Array(this.n).fill(false);
    this.betLevel = 1;          // 当前注额档位（暗注单位）
    this.betCount = 0;          // 下注动作计数（防无限闷）
    this.result = null;
    // 底注
    for (let i = 0; i < this.n; i++) this._pay(i, this.base);
    this.events.push({ kind: 'ante', base: this.base });
    this.actor = (this.button + 1) % this.n; // 庄家下家先动
    if (this.n === 1) this.actor = 0;
  }

  _pay(seat, amt) {
    const real = Math.min(amt, this.stacks[seat]);
    this.stacks[seat] -= real;
    this.committed[seat] += real;
    return real;
  }

  /** 某座位跟一档注的实际金额 */
  callAmount(seat) { return this.betLevel * this.base * (this.looked[seat] ? 2 : 1); }
  pot() { return this.committed.reduce((a, b) => a + b, 0); }
  alive() { const r = []; for (let i = 0; i < this.n; i++) if (!this.folded[i]) r.push(i); return r; }

  _prevAlive(seat) {
    for (let k = 1; k < this.n; k++) {
      const s = (seat - k + this.n) % this.n;
      if (!this.folded[s]) return s;
    }
    return -1;
  }

  _nextActor(from) {
    for (let k = 1; k <= this.n; k++) {
      const s = (from + k) % this.n;
      if (!this.folded[s]) return s;
    }
    return -1;
  }

  /**
   * 行动：
   *  look 看牌 | fold 弃牌 | call 跟注 | raise 加注（档位+1）
   *  compare 比牌 {target?}（默认上家；费用=2 倍当前注；平局发起者输）
   */
  act(seat, action) {
    if (this.result) throw new Error('hand over');
    if (seat !== this.actor) throw new Error('not your turn');
    const { type } = action;

    if (type === 'look') {
      if (this.looked[seat]) throw new Error('already looked');
      this.looked[seat] = true;
      this.events.push({ kind: 'look', seat });
    } else if (type === 'fold') {
      this.folded[seat] = true;
      this.events.push({ kind: 'fold', seat, looked: this.looked[seat] });
    } else if (type === 'call' || type === 'raise') {
      if (type === 'raise') {
        if (this.betLevel >= this.maxLevel) throw new Error('已到顶注');
        this.betLevel += 1;
      }
      const amt = this.callAmount(seat);
      const paid = this._pay(seat, amt);
      this.betCount++;
      this.events.push({ kind: type, seat, amount: paid, level: this.betLevel, allin: this.stacks[seat] === 0 });
    } else if (type === 'compare') {
      const target = action.target !== undefined ? action.target : this._prevAlive(seat);
      if (!Number.isInteger(target) || target < 0 || target >= this.hole.length || target === seat || this.folded[target]) {
        throw new Error('bad compare target');
      }
      const cost = this.callAmount(seat) * 2;
      const paid = this._pay(seat, cost);
      this.betCount++;
      const r = compare3(this.hole[seat], this.hole[target], this.allow235);
      // 平局发起者输
      const loser = r > 0 ? target : seat;
      const winner = loser === seat ? target : seat;
      this.folded[loser] = true;
      this.events.push({
        kind: 'compare', seat, target, amount: paid,
        winner, loser, tie: r === 0,
        hands: { [seat]: handName(eval3(this.hole[seat])), [target]: handName(eval3(this.hole[target])) },
      });
    } else {
      throw new Error('unknown action');
    }

    const al = this.alive();
    if (al.length === 1) return this._win(al[0], false);
    if (this.betCount >= this.maxRounds * this.n) return this._forceShowdown();
    this.actor = this._nextActor(seat);
    return { ok: true };
  }

  _win(winner, showdown) {
    const total = this.pot();
    const deltas = this.committed.map((c, i) => (i === winner ? total : 0) - c);
    this.result = {
      winner, pot: total, deltas, showdown,
      hands: showdown ? this.hole.map((h, i) => this.folded[i] ? null : handName(eval3(h))) : null,
    };
    this.events.push({ kind: 'over', result: { ...this.result } });
  }

  _forceShowdown() {
    const al = this.alive();
    let best = al[0];
    for (const s of al.slice(1)) {
      if (compare3(this.hole[s], this.hole[best], this.allow235) > 0) best = s;
    }
    this._win(best, true);
  }

  getState(seat) {
    return {
      seats: [...this.seatIds],
      base: this.base,
      hole: this.hole[seat] ? [...this.hole[seat]] : [],
      looked: [...this.looked],
      folded: [...this.folded],
      stacks: [...this.stacks],
      committed: [...this.committed],
      pot: this.pot(),
      betLevel: this.betLevel,
      callAmount: this.result ? 0 : this.callAmount(seat),
      compareCost: this.result ? 0 : this.callAmount(seat) * 2,
      actor: this.actor,
      button: this.button,
      result: this.result ? { ...this.result } : null,
    };
  }

  drainEvents() { const e = this.events; this.events = []; return e; }

  /**
   * 导演模式（温和版）：若 seat 是单张或小对子，则换成全场最好的一手
   * （避开豹子/同花顺，免得太假）；本身已不错则不动。
   */
  rigFor(seat) {
    if (this.result) return;
    if (seat < 0 || seat >= this.n) return;
    const myEval = eval3(this.hole[seat]);
    // 单张，或对子小于 8 → 算弱
    const weak = myEval.cat === 0 || (myEval.cat === 1 && myEval.tb[0] < 8);
    if (!weak) return;
    let best = -1, bestEval = null;
    for (let i = 0; i < this.n; i++) {
      if (i === seat) continue;
      const e = eval3(this.hole[i]);
      if (e.cat >= 4) continue; // 避开同花顺/豹子
      if (!bestEval || cmpScore(e, bestEval) > 0) { bestEval = e; best = i; }
    }
    if (best === -1 || cmpScore(bestEval, myEval) <= 0) return; // 没有更好的，不换
    const tmp = this.hole[seat];
    this.hole[seat] = this.hole[best];
    this.hole[best] = tmp;
  }
}

module.exports = { ZhaGame, eval3, cmpScore, compare3, handName, is235, CAT_NAMES };
