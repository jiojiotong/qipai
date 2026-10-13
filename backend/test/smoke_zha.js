'use strict';
/** 冒烟测试：走真实 HTTP+WS，打完一整局炸金花（5 人，4 机器人） */
const WebSocket = require('ws');

const BASE = 'http://127.0.0.1:' + (process.env.SMOKE_PORT || '3111');
async function api(p, opt = {}) {
  const r = await fetch(BASE + p, { ...opt, headers: { 'Content-Type': 'application/json', ...(opt.headers || {}) } });
  const j = await r.json();
  if (!r.ok) throw new Error(p + ' -> ' + (j.error || r.status));
  return j;
}

(async () => {
  const SU = process.env.SMOKE_USER || 'zha_smoke';
  const SP = process.env.SMOKE_PASS || '1234';
  let u;
  try { u = await api('/api/register', { method: 'POST', body: JSON.stringify({ name: SU, password: SP }) }); }
  catch { u = await api('/api/login', { method: 'POST', body: JSON.stringify({ name: SU, password: SP }) }); }
  const H = { 'Authorization': 'Bearer ' + u.token };
  console.log('登录 ok，金币:', u.user.coins);
  await api('/api/admin/config', { method: 'PUT', headers: H, body: JSON.stringify({ key: 'bot_delay_ms', value: '50' }) });

  const coinsBefore = (await api('/api/me', { headers: H })).user.coins;

  const ws = new WebSocket('ws://127.0.0.1:' + (process.env.SMOKE_PORT || '3111') + '/ws');
  let mySeat = 0, actions = 0, states = 0;
  const over = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('超时未结束')), 120000);
    ws.on('message', (raw) => {
      const m = JSON.parse(raw);
      if (m.t === 'hello') {
        ws.send(JSON.stringify({ t: 'room.create', game: 'zha', seats: 5 }));
      } else if (m.t === 'room.state') {
        console.log('房间', m.roomId, 'game=' + m.game, 'seats=' + m.seats.length);
        if (m.game !== 'zha') reject(new Error('房间类型不对: ' + m.game));
      } else if (m.t === 'game.state') {
        if (m.game !== 'zha') return reject(new Error('game.state 类型不对'));
        onState(m.state);
      } else if (m.t === 'game.event') {
        if (m.event && m.event.kind === 'compare') {
          console.log(`比牌: ${m.event.seat} vs ${m.event.target} → ${m.event.winner} 胜${m.event.tie ? '(平局发起者输)' : ''}`);
        }
      } else if (m.t === 'game.over') {
        if (m.game !== 'zha') return reject(new Error('game.over 类型不对'));
        clearTimeout(timer);
        resolve(m);
      } else if (m.t === 'error') {
        console.log('服务端错误:', m.msg);
      }
    });
    function onState(st) {
      states++;
      if (st.result) return;
      if (st.actor !== mySeat) return;
      // 简单策略：没看牌先看牌，然后跟注；注太大就弃
      let a;
      const looked = st.looked[mySeat];
      if (!looked) a = { type: 'look' };
      else if (st.callAmount <= 100) a = { type: 'call' };
      else a = { type: 'fold' };
      actions++;
      ws.send(JSON.stringify({ t: 'game.zha', action: a }));
    }
    ws.on('open', () => ws.send(JSON.stringify({ t: 'auth', token: u.token })));
  });

  const result = await over;
  console.log('对局结束！state 数:', states, '我的动作数:', actions);
  const deltas = result.result.deltas;
  const sum = deltas.reduce((a, b) => a + b, 0);
  console.log('deltas:', deltas.join(','), '零和:', sum === 0 ? '✅' : '❌');
  if (sum !== 0) throw new Error('非零和');
  console.log('winner:', result.result.winner, 'showdown:', result.result.showdown,
    '牌型:', (result.result.hands || []).filter(Boolean).join(','));
  const me = await api('/api/me', { headers: H });
  const dc = me.user.coins - coinsBefore;
  console.log('金币', coinsBefore, '→', me.user.coins, dc === deltas[mySeat] ? '(结算一致✅)' : `(不一致❌ 差${dc - deltas[mySeat]})`);
  if (dc !== deltas[mySeat]) throw new Error('金币结算不一致');
  const games = await api('/api/admin/games', { headers: H });
  console.log('对局记录:', games.length, '最新:', games[0] && games[0].game);
  if (!games[0] || games[0].game !== 'zha') throw new Error('对局记录类型不对');
  await api('/api/admin/config', { method: 'PUT', headers: H, body: JSON.stringify({ key: 'bot_delay_ms', value: '900' }) });
  ws.close();
  console.log('ZHA SMOKE OK');
  process.exit(0);
})().catch(e => { console.error('SMOKE FAIL:', e.message); process.exit(1); });
