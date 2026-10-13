'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { analyze, canBeat, findPlays, DoudizhuGame, rank } = require('../src/games/doudizhu');
const { chooseBid, choosePlay } = require('../src/games/doudizhu_bot');

// 构造牌：用 rank 直接拼 id（suit 轮换，保证 id 唯一）
function C(...ranks) {
  const used = new Map();
  return ranks.map(r => {
    let id;
    if (r === 16) id = 52;
    else if (r === 17) id = 53;
    else {
      const k = (used.get(r) || 0);
      used.set(r, k + 1);
      id = (r - 3) * 4 + (k % 4);
    }
    return id;
  });
}
const T = (cards) => analyze(C(...cards)).type;
const M = (cards) => analyze(C(...cards)).main;

test('牌型判定', () => {
  assert.equal(T([16, 17]), 'rocket');
  assert.equal(T([5, 5, 5, 5]), 'bomb');
  assert.equal(T([7]), 'single');
  assert.equal(T([9, 9]), 'pair');
  assert.equal(T([10, 10, 10]), 'trio');
  assert.equal(T([10, 10, 10, 3]), 'trio1');
  assert.equal(T([10, 10, 10, 3, 3]), 'trio2');
  assert.equal(T([3, 4, 5, 6, 7]), 'straight');
  assert.equal(T([3, 4, 5, 6, 7, 8, 9, 10]), 'straight');
  assert.equal(T([3, 3, 4, 4, 5, 5]), 'pairStraight');
  assert.equal(T([7, 7, 7, 8, 8, 8]), 'plane');
  assert.equal(T([7, 7, 7, 8, 8, 8, 3, 4]), 'plane1');
  assert.equal(T([7, 7, 7, 8, 8, 8, 3, 3, 4, 4]), 'plane2');
  assert.equal(T([9, 9, 9, 9, 3, 5]), 'four2');
  // 非法
  assert.equal(analyze(C(3, 4, 5, 6)), null);            // 4 张顺子
  assert.equal(analyze(C(3, 3, 4, 4)), null);            // 2 连对不够
  assert.equal(analyze(C(15, 15, 15, 15)).type, 'bomb'); // 四个2是炸弹
  assert.equal(analyze(C(15, 15, 15, 15, 3)), null);     // 炸弹不能带牌（5张非三带二）
  assert.equal(analyze(C(13, 14, 15, 16, 3)), null);     // 顺子不能含2/王（K A 2…）
  assert.equal(T([14, 14, 14, 15, 15]), 'trio2');        // 三带二可带对2
  assert.equal(M([3, 4, 5, 6, 7]), 7);                   // 顺子 main 取最大
  assert.equal(M([7, 7, 7, 8, 8, 8, 3, 4]), 8);
});

test('大小比较', () => {
  const A = (c) => analyze(C(...c));
  assert.ok(canBeat(A([5]), A([3])));                    // 单张大过
  assert.ok(!canBeat(A([3]), A([5])));
  assert.ok(canBeat(A([6, 6, 6, 6]), A([17, 17, 17])));  // 炸弹大过三张
  assert.ok(canBeat(A([16, 17]), A([6, 6, 6, 6])));      // 王炸大过炸弹
  assert.ok(!canBeat(A([6, 6, 6, 6]), A([16, 17])));
  assert.ok(canBeat(A([8, 8, 8, 8]), A([6, 6, 6, 6])));  // 炸弹比大
  assert.ok(!canBeat(A([3, 4, 5, 6, 7]), A([8, 8, 8, 8]))); // 顺子大不过炸弹
  assert.ok(!canBeat(A([3, 3]), A([4])));                // 牌型不同
  assert.ok(!canBeat(A([3, 4, 5, 6, 7]), A([8, 9, 10, 11, 12, 13]))); // 张数不同
  assert.ok(canBeat(A([8, 9, 10, 11, 12]), A([3, 4, 5, 6, 7])));     // 同张数顺子比大
  assert.ok(canBeat(A([5]), null));                     // 首出任意
});

test('findPlays 能找出大过的牌', () => {
  const hand = C(3, 3, 4, 5, 5, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17);
  const last = analyze(C(4, 4));
  const plays = findPlays(hand, last);
  assert.ok(plays.length > 0);
  for (const p of plays) assert.ok(canBeat(p.info, last), '找出的牌必须能大过');
  // 首出：至少能出单张
  const leads = findPlays(C(3, 5, 7), null);
  assert.ok(leads.some(p => p.info.type === 'single'));
});

function simulate(seed) {
  const game = new DoudizhuGame(['bot0', 'bot1', 'bot2'], { seed, baseScore: 100 });
  let guard = 0;
  while (game.phase !== 'over' && guard++ < 10000) {
    if (game.phase === 'bid') {
      const s = game.bidTurn;
      game.bid(s, chooseBid(game.hands[s], game.bidMax));
    } else {
      const s = game.turn;
      const last = game.lastPlay;
      const mv = choosePlay(game.hands[s], last ? last.info : null,
        { seat: s, landlord: game.landlord, lastSeat: last ? last.seat : -1 });
      if (mv) game.play(s, mv.cards);
      else game.pass(s);
    }
  }
  assert.equal(game.phase, 'over', `seed ${seed} 未正常结束`);
  return game;
}

test('仿真 200 局：正常结束 + 零和 + 胜者出完', () => {
  for (let seed = 1; seed <= 200; seed++) {
    const g = simulate(seed);
    const r = g.result;
    assert.equal(g.hands[r.winner].length, 0, `seed ${seed} 胜者手牌未出完`);
    const sum = r.deltas[0] + r.deltas[1] + r.deltas[2];
    assert.equal(sum, 0, `seed ${seed} 得分非零和: ${r.deltas}`);
    assert.ok(r.mult >= 1 && r.base > 0);
    assert.ok([0, 1, 2].includes(r.landlord));
  }
});

test('非法操作抛错', () => {
  const g = new DoudizhuGame(['a', 'b', 'c'], { seed: 7 });
  assert.throws(() => g.bid(1, 2), /not your bid turn/);
  assert.throws(() => g.bid(0, 5), /bad score/);
  g.bid(0, 1); g.bid(1, 0); g.bid(2, 0);
  assert.equal(g.phase, 'play');
  assert.equal(g.landlord, 0);
  assert.equal(g.hands[0].length, 20); // 地主 17+3
  assert.throws(() => g.play(0, []), /invalid play/);
  assert.throws(() => g.pass(0), /cannot pass on lead/);
  // 视图隐藏他人手牌
  const st = g.getState(1);
  assert.equal(st.hand.length, 17);
  assert.deepEqual(st.handCounts, [20, 17, 17]);
});

test('全不叫则重发', () => {
  const g = new DoudizhuGame(['a', 'b', 'c'], { seed: 42 });
  const firstHand = [...g.hands[0]];
  g.bid(0, 0); g.bid(1, 0); g.bid(2, 0);
  assert.equal(g.phase, 'bid'); // 重发后回到叫分
  assert.notDeepEqual(g.hands[0], firstHand);
});
