'use strict';
/** 冒烟测试：走真实 HTTP+WS，打完一整局德州扑克（6 人，5 机器人） */
const WebSocket = require('ws');

const BASE = 'http://127.0.0.1:' + (process.env.SMOKE_PORT || '3111');
async function api(p, opt = {}) {
  const r = await fetch(BASE + p, { ...opt, headers: { 'Content-Type': 'application/json', ...(opt.headers || {}) } });
  const j = await r.json();
  if (!r.ok) throw new Error(p + ' -> ' + (j.error || r.status));
  return j;
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const SU = process.env.SMOKE_USER || 'tx_smoke';
  const SP = process.env.SMOKE_PASS || '1234';
  let u;
  try { u = await api('/api/register', { method: 'POST', body: JSON.stringify({ name: SU, password: SP }) }); }
  catch { u = await api('/api/login', { method: 'POST', body: JSON.stringify({ name: SU, password: SP }) }); }
  const H = { 'Authorization': 'Bearer ' + u.token };
  console.log('登录 ok，金币:', u.user.coins);
  await api('/api/admin/config', { method: 'PUT', headers: H, body: JSON.stringify({ key: 'bot_delay_ms', value: '50' }) });
  await api('/api/admin/config', { method: 'PUT', headers: H, body: JSON.stringify({ key: 'texas_bb', value: '10' }) });

  const list = await api('/api/me', { headers: H });
  const coinsBefore = list.user.coins;

  const ws = new WebSocket('ws://127.0.0.1:' + (process.env.SMOKE_PORT || '3111') + '/ws');
  let mySeat = 0, actions = 0, states = 0, sawShowdown = false;
  const over = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('超时未结束')), 120000);
    ws.on('message', (raw) => {
      const m = JSON.parse(raw);
      if (m.t === 'hello') {
        ws.send(JSON.stringify({ t: 'room.create', game: 'texas', seats: 6 }));
      } else if (m.t === 'room.state') {
        console.log('房间', m.roomId, 'game=' + m.game, 'seats=' + m.seats.length);
        if (m.game !== 'texas') reject(new Error('房间类型不对: ' + m.game));
      } else if (m.t === 'game.state') {
        if (m.game !== 'texas') return reject(new Error('game.state 类型不对'));
        onState(m.state);
      } else if (m.t === 'game.over') {
        if (m.game !== 'texas') return reject(new Error('game.over 类型不对'));
        clearTimeout(timer);
        resolve(m);
      } else if (m.t === 'error') {
        console.log('服务端错误:', m.msg);
      }
    });
    function onState(st) {
      states++;
      if (st.street === 'over' || st.result) return;
      if (st.actor !== mySeat) return;
      let a;
      if (st.toCall === 0) a = { type: 'check' };
      else if (st.toCall <= 60) a = { type: 'call' };
      else a = { type: 'fold' };
      actions++;
      ws.send(JSON.stringify({ t: 'game.act', action: a }));
    }
    ws.on('open', () => ws.send(JSON.stringify({ t: 'auth', token: u.token })));
  });

  const result = await over;
  console.log('对局结束！state 数:', states, '我的动作数:', actions);
  const deltas = result.result.deltas;
  const sum = deltas.reduce((a, b) => a + b, 0);
  console.log('deltas:', deltas.join(','), '零和:', sum === 0 ? '✅' : '❌');
  if (sum !== 0) throw new Error('非零和');
  if (result.result.holeCards) { sawShowdown = true; console.log('摊牌亮牌 ✅'); }
  console.log('winners:', JSON.stringify(result.result.winners.map(w => ({ seats: w.seats, amount: w.amount, showdown: w.showdown }))));
  const me = await api('/api/me', { headers: H });
  console.log('金币', coinsBefore, '→', me.user.coins, me.user.coins - coinsBefore === deltas[mySeat] ? '(结算一致✅)' : '(不一致❌)');
  if (me.user.coins - coinsBefore !== deltas[mySeat]) throw new Error('金币结算不一致');
  const games = await api('/api/admin/games', { headers: H });
  console.log('对局记录:', games.length, '最新:', games[0] && games[0].game);
  if (!games[0] || games[0].game !== 'texas') throw new Error('对局记录类型不对');
  await api('/api/admin/config', { method: 'PUT', headers: H, body: JSON.stringify({ key: 'bot_delay_ms', value: '900' }) });
  ws.close();
  console.log('TEXAS SMOKE OK');
  process.exit(0);
})().catch(e => { console.error('SMOKE FAIL:', e.message); process.exit(1); });
