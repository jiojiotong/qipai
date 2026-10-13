'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { ZhaGame, eval3, cmpScore, compare3, handName, is235 } = require('../src/games/zha');
const { decide, tierOf } = require('../src/games/zha_bot');

let _deal = 0;
function C(...ranks) {
  return ranks.map(r => (r - 3) * 4 + ((_deal++) % 4));
}
function CS(suit, ...ranks) { return ranks.map(r => (r - 3) * 4 + suit); }
const gt = (a, b) => cmpScore(eval3(C(...a)), eval3(C(...b))) > 0;

test('牌型大小', () => {
  assert.ok(gt([14, 14, 14], [13, 13, 13]), '豹子比点');
  const sf = eval3(CS(1, 12, 11, 10));
  assert.equal(sf.cat, 4, '同花顺');
  assert.ok(cmpScore(eval3(C(14, 14, 14)), sf) > 0, '豹子 > 同花顺');
  assert.ok(cmpScore(sf, eval3(CS(2, 14, 12, 8))) > 0, '同花顺 > 同花');
  const fl = eval3(CS(0, 14, 11, 7));
  assert.equal(fl.cat, 3, '同花');
  assert.ok(cmpScore(fl, eval3(C(12, 11, 10))) > 0, '同花 > 顺子');
  assert.ok(gt([9, 9, 5], [8, 8, 14]), '对子先比对');
  assert.ok(gt([9, 9, 14], [9, 9, 5]), '对子比踢脚');
  assert.ok(gt([14, 13, 9], [14, 13, 8]), '单张比点');
});

test('顺子细节：A23 最小', () => {
  assert.equal(eval3(C(15, 14, 3)).tb[0], 3, 'A23 按 3 算');
  assert.ok(gt([4, 3, 2].map(r => r === 2 ? 15 : r), [15, 14, 3]), '432 > A23');
  assert.ok(gt([14, 13, 12], [5, 4, 3]), 'QKA 最大');
});

test('235 专杀豹子', () => {
  const r = compare3(C(15, 5, 3), C(14, 14, 14));
  assert.equal(r, 1, '235 赢 AAA');
  assert.equal(compare3(C(14, 14, 14), C(15, 5, 3)), -1);
  // 235 对其他牌就是最烂单张
  assert.equal(compare3(C(15, 5, 3), C(6, 4, 15)), -1, '235 输 642');
  assert.equal(compare3(C(15, 5, 3), C(14, 14, 14), false), -1, '关掉规则后 235 输豹子');
  assert.ok(is235(eval3(C(15, 5, 3))));
});

test('闷/明注额', () => {
  const g = new ZhaGame(['a', 'b', 'c'], { seed: 1, baseBet: 10, buyIn: 5000 });
  assert.equal(g.actor, 1);
  g.act(1, { type: 'call' });           // 闷跟 10
  assert.equal(g.committed[1], 20);     // 底注 10 + 跟 10
  g.act(2, { type: 'look' });
  g.act(0, { type: 'call' });           // 闷跟 10
  g.act(1, { type: 'raise' });          // 档位→2，闷付 20
  assert.equal(g.betLevel, 2);
  assert.equal(g.committed[1], 40);
  g.act(2, { type: 'call' });           // 明跟：2档×10×2=40
  assert.equal(g.committed[2], 50);
});

test('比牌：输家出局，平局发起者输', () => {
  const g = new ZhaGame(['a', 'b'], { seed: 1, baseBet: 10, buyIn: 5000 });
  g.hole = [C(14, 14, 14), C(13, 13, 13)]; // a 豹子 A，b 豹子 K
  g.act(1, { type: 'compare' });            // b 找上家 a 比
  assert.ok(g.result, 'b 输，a 直接赢');
  assert.equal(g.result.winner, 0);
  // 平局
  const g2 = new ZhaGame(['a', 'b'], { seed: 1, baseBet: 10, buyIn: 5000 });
  g2.hole = [C(9, 9, 5), C(9, 9, 5)];
  g2.act(1, { type: 'compare' });
  assert.equal(g2.result.winner, 0, '平局发起者 b 输');
});

test('顶注限制', () => {
  const g = new ZhaGame(['a', 'b'], { seed: 1, baseBet: 10, buyIn: 100000, maxLevel: 3 });
  g.act(1, { type: 'raise' }); // 2
  g.act(0, { type: 'raise' }); // 3
  assert.throws(() => g.act(1, { type: 'raise' }), /顶注/, '到顶不能再加');
});

test('超轮强制亮牌', () => {
  const g = new ZhaGame(['a', 'b', 'c'], { seed: 1, baseBet: 10, buyIn: 5000, maxRounds: 1 });
  g.hole = [C(7, 5, 4), C(14, 14, 14), C(9, 9, 5)];
  g.act(1, { type: 'call' });
  g.act(2, { type: 'call' });
  g.act(0, { type: 'call' }); // 第 3 个下注动作 → 强制亮牌
  assert.ok(g.result && g.result.showdown, '强制摊牌');
  assert.equal(g.result.winner, 1, '豹子 A 赢');
});

function playHand(seed, n) {
  const seats = Array.from({ length: n }, (_, i) => 'p' + i);
  const g = new ZhaGame(seats, { seed, baseBet: 10, buyIn: 5000 });
  let guard = 0;
  while (!g.result && guard++ < 5000) {
    const s = g.actor;
    g.act(s, decide(g, s));
  }
  if (!g.result) throw new Error(`seed ${seed}: 未结束`);
  return g;
}

test('仿真 500 局（2~6 人）：完成 + 零和', () => {
  for (let seed = 1; seed <= 500; seed++) {
    const n = 2 + (seed % 5);
    const g = playHand(seed, n);
    const sum = g.result.deltas.reduce((a, b) => a + b, 0);
    assert.equal(sum, 0, `seed ${seed} n=${n} 非零和`);
  }
});

test('仿真 100 局（8 人满桌）', () => {
  for (let seed = 9001; seed <= 9100; seed++) {
    const g = playHand(seed, 8);
    assert.equal(g.result.deltas.reduce((a, b) => a + b, 0), 0);
  }
});
