const {test} = require('node:test');
const assert = require('node:assert/strict');
const M = require('../Model.js');
const minute = 60000;
const noon = Date.parse('2026-09-09T12:00:00Z');
const e = (name, at) => ({name, at, time: '12:00'});
const schedule = {identity:'fixture',days:[{events:[e('Dhuhr',noon), e('Asr',noon+180*minute)]}]};
const phase = (at, s=schedule) => M.phase(s,at,30,30);
test('bar countdown follows selected reminder windows and disappears after dismissal',()=>{
  const cfg={countdown:true,countdownWindow:'both'},before=phase(noon-15*minute),after=phase(noon+5*minute);
  assert.deepEqual(M.barCountdown(before,{},cfg,noon-15*minute),{name:'Dhuhr',stage:'before',remaining:'15m'});
  assert.deepEqual(M.barCountdown(after,{},cfg,noon+5*minute),{name:'Dhuhr',stage:'after',remaining:'25m'});
  assert.equal(M.barCountdown(before,{}, {...cfg,countdownWindow:'after'},noon-minute),null);
  assert.equal(M.barCountdown(after,{}, {...cfg,countdownWindow:'before'},noon+minute),null);
  assert.equal(M.barCountdown(before,{}, {...cfg,countdown:false},noon-minute),null);
  assert.equal(M.barCountdown(phase(noon-31*minute),{},cfg,noon-31*minute),null);
  assert.equal(M.barCountdown(after,{},cfg,noon+30*minute),null);
  assert.equal(M.barCountdown(before,M.remember({},'acknowledged',before.key),cfg,noon-minute),null);
  assert.equal(M.barCountdown(phase(noon),M.remember({},'acknowledged',before.key),cfg,noon).remaining,'30m');
});

test('repeated failures back off from one minute to a fifteen-minute ceiling', () => {
  assert.deepEqual([1,2,3,4,5,100].map(n=>M.retryDelayMs(n)),[1,2,4,8,15,15].map(n=>n*minute));
});
test('automatic retries never precede the server Retry-After delay', () => {
  assert.equal(M.retryDelayMs(1,600),10*minute);
  assert.equal(M.retryDelayMs(5,3600),60*minute);
  assert.equal(M.retryDelayMs(1,0),minute);
  for (const invalid of [-1,NaN,Infinity,'600',null]) assert.equal(M.retryDelayMs(1,invalid),minute);
});

test('normal until exactly 30 minutes before; approaching until the prayer starts', () => {
  assert.equal(phase(noon-30*minute-1).stage,'normal');
  assert.equal(phase(noon-30*minute).stage,'before');
  assert.equal(phase(noon-1).stage,'before');
});
test('green at the prayer time, normal exactly 30 minutes later', () => {
  assert.equal(phase(noon).stage,'after');
  assert.equal(phase(noon+30*minute-1).stage,'after');
  assert.equal(phase(noon+30*minute).stage,'normal');
});
test('click dismissal persists but approaching dismissal does not silence the green phase', () => {
  const p=phase(noon-minute);
  const state=M.remember({},'acknowledged',p.key);
  assert.equal(M.visualStage(p,JSON.parse(JSON.stringify(state))),'normal');
  assert.equal(M.visualStage(phase(noon),state),'after');
  assert.equal(M.visualStage(phase(noon+170*minute),state),'before');
});
test('approaching Fajr and Dhuhr are yellow; other approaching prayers are red', () => {
  for (const name of M.PRAYERS) {
    const s={identity:'colours',days:[{events:[e(name,noon)]}]};
    const p=phase(noon-minute,s);
    assert.equal(M.reminderColor(M.visualStage(p,{}),p.prayer.name,'#ffffff'),
      ['Fajr','Dhuhr'].includes(name) ? '#e9c46a' : '#ee7474',name);
    const dismissed=M.remember({},'acknowledged',p.key);
    assert.equal(M.reminderColor(M.visualStage(p,dismissed),p.prayer.name,'#ffffff'),'#ffffff',name+' dismissed');
    const after=phase(noon,s);
    assert.equal(M.reminderColor(M.visualStage(after,dismissed),after.prayer.name,'#ffffff'),'#65c98b',name+' started');
  }
  assert.equal(M.reminderColor('normal',null,'#ffffff'),'#ffffff');
});
test('a just-started prayer takes precedence over an overlapping pre-prayer window', () => {
  const s={identity:'short',days:[{events:[e('Maghrib',noon),e('Isha',noon+40*minute)]}]};
  assert.equal(phase(noon+20*minute,s).stage,'after');
  assert.equal(phase(noon+30*minute,s).stage,'before');
});
test('midnight preserves yesterday’s green period and uses tomorrow’s actual Fajr', () => {
  const midnight=Date.parse('2026-09-10T00:00:00Z');
  const s={identity:'night',days:[
    {events:[e('Isha',midnight-10*minute)]},
    {events:[e('Fajr',midnight+313*minute)]}
  ]};
  assert.equal(phase(midnight,s).stage,'after');
  assert.equal(phase(midnight+284*minute,s).prayer.at,midnight+313*minute);
});
test('sunrise is informational and never produces a prayer alert', () => {
  const s={identity:'sun',days:[{events:[e('Sunrise',noon)]}]};
  assert.equal(phase(noon,s).stage,'normal');
  assert.equal(phase(noon-minute,s).stage,'normal');
});
test('missing and expired schedules cannot invent tomorrow’s prayer times', () => {
  assert.equal(phase(noon,null).stage,'normal');
  assert.equal(phase(noon+1440*minute).next,null);
  assert.equal(phase(noon+1440*minute).stage,'normal');
});
test('notifications happen once per phase across polling and restart', () => {
  const p=phase(noon);
  assert.equal(M.shouldNotify(p,noon,noon-1000,{}),true);
  const state=M.remember({},'notified',p.key);
  assert.equal(M.shouldNotify(p,noon,noon-1000,state),false);
  assert.equal(M.shouldNotify(p,noon,0,{}),false);
  assert.equal(M.shouldNotify(p,noon+minute,noon-120*minute,{}),false);
  assert.equal(M.shouldNotify(p,noon,noon+1000,{}),false);
  assert.equal(M.shouldNotify(p,noon,noon-1000,M.remember({},'acknowledged',p.key)),false);
});
test('local-day boundaries use schedule timestamps, independent of system timezone', () => {
  const s={days:[{date:'2026-09-09',start:noon-15*60*minute,end:noon+9*60*minute}]};
  assert.equal(M.dayAt(s,noon).date,'2026-09-09');
  assert.equal(M.dayAt(s,noon+9*60*minute),null);
});
