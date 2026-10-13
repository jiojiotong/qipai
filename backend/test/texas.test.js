'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { TexasGame, eval5, eval7, cmpScore, handName } = require('../src/games/texas');
const { decide, chenScore } = require('../src/games/texas_bot');

// 用 rank 拼 id：全局轮转发花色（模拟真实发牌），同一次调用内 id 唯一
let _deal = 0;
function C(...ranks) {
  return ranks.map(r => {
    if (r === 16) return 52;
    if (r === 17) return 53;
    return (r - 3) * 4 + ((_deal++) % 4);
  });
}
// 同花：指定 suit
function CS(suit, ...ranks) { return ranks.map(r => (r - 3) * 4 + suit); }
const gt = (a, b) => cmpScore(eval5(C(...a)), eval5(C(...b))) > 0;
const gtIds = (a, b) => cmpScore(eval5(a), eval5(b)) > 0;

test('比牌：牌型大小', () => {
  assert.ok(gt([14, 13, 12, 11, 10], [13, 12, 11, 10, 9]));       // 皇家 > 同花顺
  assert.ok(gtIds(CS(2, 13, 12, 11, 10, 9), C(9, 9, 9, 9, 5)), '真同花顺 > 四条');
  assert.ok(gt([9, 9, 9, 9, 5], [14, 14, 14, 13, 13]));           // 四条 > 葫芦
  assert.ok(gt([14, 14, 14, 13, 13], [14, 13, 11, 9, 7]));        // 葫芦 > 同花（同花色构造见下）
  assert.ok(gtIds(CS(1, 14, 12, 10, 8, 6), C(9, 8, 7, 6, 5)), '真同花 > 普通顺子');
  assert.ok(gt([9, 8, 7, 6, 5], [9, 9, 9, 5, 4]));                // 顺子 > 三条
  assert.ok(gt([9, 9, 9, 5, 4], [14, 14, 5, 5, 9]));              // 三条 > 两对
  assert.ok(gt([14, 14, 5, 5, 9], [14, 14, 5, 4, 3]));            // 两对 > 一对
  assert.ok(gt([14, 14, 5, 4, 3], [14, 13, 11, 9, 7]));          // 一对 > 高牌
});

test('比牌：同花与顺子细节', () => {
  const flushA = eval5(CS(1, 14, 12, 10, 8, 6));
  const flushB = eval5(CS(2, 14, 13, 11, 9, 7));
  assert.ok(cmpScore(flushB, flushA) > 0, '同花比第二张');
  assert.equal(eval5(C(14, 5, 4, 3, 15)).tb[0], 5, 'A2345 顺子按 5 算');
  assert.ok(gt([6, 5, 4, 3, 15], [14, 5, 4, 3, 15]), '6 高顺子 > 轮子');
  const sfWheel = eval5(CS(0, 14, 5, 4, 3, 15));
  assert.equal(sfWheel.cat, 8, '同花轮子也是同花顺');
});

test('比牌：踢脚与平分', () => {
  assert.ok(gt([14, 14, 13, 12, 11], [14, 14, 13, 12, 10]), '踢脚大者胜');
  assert.equal(cmpScore(eval5(C(14, 13, 12, 11, 10)), eval5(C(14, 13, 12, 11, 10))), 0, '完全相同平分');
  // 葫芦：先比三条，三条相同再比对子
  assert.ok(gt([9, 9, 9, 14, 14], [9, 9, 9, 5, 5]), '同三条比对子');
});

test('eval7 取最优', () => {
  const s = eval7(C(14, 14, 14, 14, 5, 6, 7));
  assert.equal(s.cat, 7, '四条');
  const s2 = eval7([...CS(1, 14, 13, 12, 11, 10), ...C(2, 3)]);
  assert.equal(s2.cat, 8, '7 张中同花顺');
  assert.equal(handName(s2), '同花顺');
});

test('边池', () => {
  const g = new TexasGame(['a', 'b', 'c'], { seed: 1, smallBlind: 10, bigBlind: 20, buyIn: 1000 });
  g.committed = [100, 300, 300];
  g.roundBet = [0, 0, 0]; // 假设盲注已并入 committed
  g.stacks = [0, 700, 700];
  g.folded = [false, false, false];
  g.board = C(9, 8, 7, 5, 4);
  g.hole = [C(14, 14), C(13, 13), C(7, 15)]; // A:AA B:KK C:72o（2 即 rank15）
  g._showdown();
  const r = g.result;
  assert.deepEqual(r.deltas, [200, 100, -300], '边池分配 ' + JSON.stringify(r.deltas));
  assert.equal(r.deltas[0] + r.deltas[1] + r.deltas[2], 0, '零和');
});

test('不战而胜（全 fold）', () => {
  const g = new TexasGame(['a', 'b', 'c'], { seed: 2 });
  // 翻牌前：a(UTG) fold, b(SB) fold → c(BB) 直接赢
  const order = [];
  while (!g.result) {
    const s = g.actor;
    order.push(s);
    if (s === 2) break;
    g.act(s, { type: 'fold' });
  }
  assert.deepEqual(order, [0, 1]);
  assert.ok(g.result, 'c 获胜');
  assert.equal(g.result.winners[0].seats[0], 2);
  const pot = g.result.pot;
  assert.equal(g.result.deltas[2], pot - 20, '赢家净胜=底池-自己盲注');
});

test('下注规则校验', () => {
  const g = new TexasGame(['a', 'b'], { seed: 3, smallBlind: 10, bigBlind: 20, buyIn: 1000 });
  // 单挑：button=SB=a 先动，toCall=10
  assert.equal(g.actor, 0);
  assert.throws(() => g.act(0, { type: 'check' }), /cannot check/, '面对下注不能 check');
  assert.throws(() => g.act(0, { type: 'raise', amount: 25 }), /raise too small/, '加注不足最小');
  g.act(0, { type: 'call' });
  assert.equal(g.actor, 1, '轮到 BB');
  g.act(1, { type: 'check' }); // BB 选择不加注
  assert.equal(g.street, 'flop', '进入翻牌');
  assert.equal(g.board.length, 3);
});

test('最小加注更新', () => {
  const g = new TexasGame(['a', 'b', 'c'], { seed: 4, smallBlind: 10, bigBlind: 20, buyIn: 1000 });
  // UTG=a 加注到 60（+40），minRaise 变成 40
  g.act(0, { type: 'raise', amount: 60 });
  assert.equal(g.minRaise, 40);
  assert.throws(() => g.act(1, { type: 'raise', amount: 80 }), /raise too small/, '需至少 +40');
  g.act(1, { type: 'raise', amount: 100 }); // +40 合法
  assert.equal(g.currentBet, 100);
});

function playHand(seed, n) {
  const seats = Array.from({ length: n }, (_, i) => 'p' + i);
  const g = new TexasGame(seats, { seed, smallBlind: 10, bigBlind: 20, buyIn: 2000 });
  let guard = 0;
  while (!g.result && guard++ < 3000) {
    const s = g.actor;
    if (s === -1) throw new Error(`seed ${seed}: 无人可行动但未结束`);
    g.act(s, decide(g, s));
  }
  if (!g.result) throw new Error(`seed ${seed}: 未结束`);
  return g;
}

test('仿真 500 局（6 人）：完成 + 零和', () => {
  for (let seed = 1; seed <= 500; seed++) {
    const g = playHand(seed, 6);
    const sum = g.result.deltas.reduce((a, b) => a + b, 0);
    assert.equal(sum, 0, `seed ${seed} 非零和`);
    assert.equal(g.street, 'over');
  }
});

test('仿真 200 局（单挑 + 9 人）', () => {
  for (let seed = 1001; seed <= 1100; seed++) {
    const g = playHand(seed, 2);
    assert.equal(g.result.deltas.reduce((a, b) => a + b, 0), 0);
  }
  for (let seed = 2001; seed <= 2100; seed++) {
    const g = playHand(seed, 9);
    assert.equal(g.result.deltas.reduce((a, b) => a + b, 0), 0);
  }
});

test('全员 all-in 直接发完摊牌', () => {
  const g = new TexasGame(['a', 'b'], { seed: 5, smallBlind: 10, bigBlind: 20, buyIn: 30 });
  // SB=button=a: 10；BB=b: 20；a 剩 20，b 剩 10
  g.act(0, { type: 'call' }); // a 跟 10，剩 10
  // b: toCall=0，check
  g.act(1, { type: 'check' });
  // 翻牌：a（按钮/SB）先动
  assert.equal(g.street, 'flop');
  assert.equal(g.actor, 0);
  g.act(0, { type: 'raise', amount: 10 }); // a all-in（不足最小下注但成立）
  // b 跟 → 双方 all-in，发完
  g.act(1, { type: 'call' });
  assert.equal(g.street, 'over', '双方 all-in 后直接结束');
  assert.ok(g.result.deltas);
});
