'use strict';
/**
 * 炸金花 AI（启发式）
 * decide(game, seat) -> {type:'look'|'fold'|'call'|'raise'|'compare', target?}
 */
const { eval3 } = require('./zha');

/** 牌力分档 3 强 / 2 中上 / 1 中 / 0 弱 */
function tierOf(hole) {
  const s = eval3(hole);
  if (s.cat >= 4) return 3;
  if (s.cat === 3) return 2;
  if (s.cat === 2) return 2;
  if (s.cat === 1) return s.tb[0] >= 11 ? 2 : 1;
  if (s.tb[0] === 14) return 1; // A 高单张
  return 0;
}

function aliveCount(game) {
  const st = game.getState(0);
  return st.folded.filter(f => !f).length;
}

function decide(game, seat) {
  const st = game.getState(seat);
  const callAmt = st.callAmount;
  const stack = st.stacks[seat];
  const cheap = callAmt <= Math.max(st.base * 2, stack * 0.05);
  const remain = aliveCount(game);

  // 未看牌：闷着玩
  if (!st.looked[seat]) {
    if (st.betLevel >= 4 || Math.random() < 0.25) return { type: 'look' };
    return cheap ? { type: 'call' } : { type: 'fold' };
  }

  const t = tierOf(st.hole);

  // 只剩 2 人：强牌直接比
  if (remain === 2 && t >= 2 && Math.random() < 0.6) return { type: 'compare' };

  if (t === 3) {
    if (st.betLevel < 8 && Math.random() < 0.7) return { type: 'raise' };
    return { type: 'call' };
  }
  if (t === 2) {
    if (Math.random() < 0.25 && st.betLevel < 8) return { type: 'raise' };
    return cheap || callAmt <= stack * 0.2 ? { type: 'call' } : { type: 'fold' };
  }
  if (t === 1) {
    return cheap ? { type: 'call' } : { type: 'fold' };
  }
  // 弱牌：偶尔诈唬式跟一手
  if (callAmt <= st.base && Math.random() < 0.3) return { type: 'call' };
  return { type: 'fold' };
}

module.exports = { decide, tierOf };
