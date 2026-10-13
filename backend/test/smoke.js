'use strict';
/** 冒烟测试：走真实 HTTP+WS，打完一整局斗地主 */
const WebSocket = require('ws');
const { chooseBid, choosePlay } = require('../src/games/doudizhu_bot');

const BASE = 'http://127.0.0.1:3110';
async function api(p, opt = {}) {
  const r = await fetch(BASE + p, { ...opt, headers: { 'Content-Type': 'application/json', ...(opt.headers || {}) } });
  const j = await r.json();
  if (!r.ok) throw new Error(p + ' -> ' + (j.error || r.status));
  return j;
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  // 注册/登录（第一个用户自动成管理员）
  let admin, p2;
  try { admin = await api('/api/register', { method: 'POST', body: JSON.stringify({ name: 'smoke_admin', password: '1234' }) }); }
  catch { admin = await api('/api/login', { method: 'POST', body: JSON.stringify({ name: 'smoke_admin', password: '1234' }) }); }
  try { p2 = await api('/api/register', { method: 'POST', body: JSON.stringify({ name: 'smoke_p2', password: '1234' }) }); }
  catch { p2 = await api('/api/login', { method: 'POST', body: JSON.stringify({ name: 'smoke_p2', password: '1234' }) }); }
  console.log('登录 ok，管理员:', admin.user.is_admin, '初始金币:', admin.user.coins);

  // 管理后台：调快机器人
  const H = { 'Authorization': 'Bearer ' + admin.token };
  await api('/api/admin/config', { method: 'PUT', headers: H, body: JSON.stringify({ key: 'bot_delay_ms', value: '50' }) });
  console.log('管理后台配置 ok');

  const coinsBefore = admin.user.coins;
  const ws = new WebSocket('ws://127.0.0.1:3110/ws');
  let mySeat = -1, done = false, actions = 0;
  const over = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('超时未结束')), 90000);
    ws.on('message', (raw) => {
      const m = JSON.parse(raw);
      if (m.t === 'hello') { ws.send(JSON.stringify({ t: 'room.create', bots: 2 })); }
      else if (m.t === 'room.state') { /* console.log('房间', m.roomId, m.seats.map(s=>s&&s.name).join(',')) */ }
      else if (m.t === 'game.state') { onState(m.state); }
      else if (m.t === 'game.over') { clearTimeout(timer); resolve(m); }
      else if (m.t === 'error') { console.log('服务端错误:', m.msg); }
    });
    const guess = 0; // 建房者恒为 0 号位
    function onState(st) {
      if (done) return;
      if (st.phase === 'bid' && st.bidTurn === guess) {
        const b = chooseBid(st.hand, Math.max(0, ...st.bids.filter(x => x !== null)));
        actions++;
        ws.send(JSON.stringify({ t: 'game.bid', score: b }));
      } else if (st.phase === 'play' && st.turn === guess) {
        const last = st.lastPlay;
        const mv = choosePlay(st.hand, last ? last.info : null,
          { seat: guess, landlord: st.landlord, lastSeat: last ? last.seat : -1 });
        actions++;
        if (mv) ws.send(JSON.stringify({ t: 'game.play', cards: mv.cards }));
        else ws.send(JSON.stringify({ t: 'game.pass' }));
      }
    }
    // 首个 game.state 来之前不知道座位：用 bids/hand 推断。简化：座位0
    ws.on('open', () => ws.send(JSON.stringify({ t: 'auth', token: admin.token })));
  });

  const result = await over;
  done = true;
  console.log('对局结束！动作数:', actions);
  console.log('结果: 地主', result.result.landlord, result.result.landlordWin ? '胜' : '负',
    '春天', result.result.spring, '炸弹', result.result.bombCount, '倍数', result.result.mult);
  console.log('玩家:', result.players.map(p => `${p.name}:${p.delta}`).join(' '));
  const me = await api('/api/me', { headers: H });
  console.log('金币', coinsBefore, '→', me.user.coins, me.user.coins !== coinsBefore ? '(已结算✅)' : '(未变化❌)');
  const games = await api('/api/admin/games', { headers: H });
  console.log('对局记录数:', games.length);
  // 恢复机器人延迟
  await api('/api/admin/config', { method: 'PUT', headers: H, body: JSON.stringify({ key: 'bot_delay_ms', value: '900' }) });
  ws.close();
  process.exit(0);
})().catch(e => { console.error('SMOKE FAIL:', e.message); process.exit(1); });
