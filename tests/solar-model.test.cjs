const {test}=require('node:test');const assert=require('node:assert/strict');const S=require('../SolarModel.js');
const Layout=require('../DialLayout.js');
const start=Date.parse('2026-09-09T00:00:00Z'),m=60000,h=60*m;
const point=(at,alt=-25,az=0,offset=0)=>[at,1,0,0,alt,az,offset];
const day={start,end:start+24*h,regime:'normal',date:'2026-09-09',events:{sunrise:start+6*h,sunset:start+18*h,solarNoon:start+12*h,civilDawn:start+5.5*h,nauticalDawn:start+5*h,astronomicalDawn:start+4.5*h,civilDusk:start+18.5*h,nauticalDusk:start+19*h,astronomicalDusk:start+19.5*h},samples:Array.from({length:1441},(_,i)=>point(start+i*m))};
const schedule={days:[{events:[{name:'Isha',at:start-4*h},{name:'Fajr',at:start+4*h},{name:'Sunrise',at:start+5.8*h},{name:'Dhuhr',at:start+12.1*h},{name:'Asr',at:start+15*h},{name:'Maghrib',at:start+18.1*h},{name:'Isha',at:start+20*h},{name:'Fajr',at:start+28*h}]}]};
test('guidance uses labelled 45/10/45 estimates with exact transitions',()=>{
 const bands=S.build(day,schedule,true).guidance;assert.equal(bands.length,3);
 assert.deepEqual(bands.map(s=>(s.end-s.start)/m),[45,10,45]);
 for(const s of bands){assert.equal(s.estimated,true);assert.ok(s.source.startsWith('https://kurul.diyanet.gov.tr/'));assert.equal(S.active([s],s.start-1),null);assert.equal(S.active([s],s.start),s);assert.equal(S.active([s],s.end),null)}
});
test('provider-adjusted sunrise and Maghrib never move astronomical events',()=>{
 const b=S.build(day,schedule,true);
 assert.equal(b.prayer.find(s=>s.name==='morning').start,start+5.8*h);
 assert.equal(b.solar.find(s=>s.name==='daylight').start,start+6*h);
 assert.equal(b.prayer.find(s=>s.name==='Maghrib').start,start+18.1*h);
 assert.equal(b.guidance[2].end,start+18*h);
});
test('expired or missing dated timetables leave gaps instead of extending Isha',()=>{
 const previous={start:start-24*h,end:start,events:[{name:'Isha',at:start-4*h}]};
 assert.equal(S.build(day,{days:[previous]},true).prayer.length,0);
 const future={start:start+24*h,end:start+48*h,events:[{name:'Fajr',at:start+28*h}]};
 assert.equal(S.build(day,{days:[previous,future]},true).prayer.length,0);
 const current={start,end:day.end,events:[{name:'Isha',at:start+20*h}]};
 assert.equal(S.build(day,{days:[current]},false).prayer[0].end,day.end);
});
test('polar, missing and overlapping bands are suppressed',()=>{
 for(const d of [{...day,regime:'polarDay'},{...day,events:{...day.events,sunrise:null}},{...day,events:{...day.events,sunrise:start+12*h}}]){
  const b=S.build(d,schedule,true);assert.equal(b.guidance.length,0);assert.equal(b.guidanceUnavailable,true)
 }
 assert.equal(S.build(day,{days:[]},true).guidanceUnavailable,true);
 assert.equal(S.build(day,schedule,false).guidanceUnavailable,false);assert.equal(S.build(day,schedule,false).guidance.length,0);
});
test('prayer and solar partitions span the day without gaps or overlapping intervals',()=>{
 const b=S.build(day,schedule,true);
 for(const list of [b.prayer,b.solar]){assert.equal(list[0].start,day.start);assert.equal(list.at(-1).end,day.end);for(let i=1;i<list.length;i++)assert.equal(list[i-1].end,list[i].start)}
 assert.equal(b.prayer[0].name,'Isha');assert.equal(b.prayer.at(-1).boundaryEnd,start+28*h);
});
test('interpolation handles azimuth wrap and DST offset transitions',()=>{
 const d={start,end:start+m,samples:[point(start,0,359,0),point(start+m,1,1,60)]};
 assert.equal(S.position(d,start+m/2).azimuth,0);assert.equal(S.position(d,start+m/2).altitude,.5);
 assert.equal(S.clock(d,start+m),'01:01');assert.equal(S.clock(d,start),'00:00');
});
test('the slider covers real elapsed time on 23 and 25-hour local days',()=>{
 for(const hours of [23,25]){const d={...day,end:start+hours*h};assert.equal(S.atFraction(d,.5),start+hours*h/2);assert.equal(S.atFraction(d,1),d.end-1);assert.equal(S.fraction(d,start+hours*h/2),.5)}
});
test('preview computations cannot mutate the schedule, ephemeris, or live state',()=>{
 const before=JSON.stringify({day,schedule});for(let f=0;f<1;f+=.03){S.build(day,schedule,true);S.position(day,S.atFraction(day,f))};assert.equal(JSON.stringify({day,schedule}),before)
});
test('camera basis points at the selected coordinates in both hemispheres',()=>{
 for(const [lat,lon] of [[0,0],[37,42],[-33,151],[90,0]]){const b=S.camera(lat,lon);for(const v of Object.values(b))assert.ok(Math.abs(v.reduce((n,x)=>n+x*x,0)-1)<1e-12);assert.ok(Math.abs(b.front.reduce((n,x,i)=>n+x*b.east[i],0))<1e-12)}
});
test('clock marks follow local hours and half-hours across DST',()=>{
 assert.equal(S.clockTicks(day).length,48);
 assert.equal(S.clockTicks(day).filter(t=>t.major).length,24);
 const spring={...day,end:start+23*h,samples:Array.from({length:1381},(_,i)=>point(start+i*m,0,0,i<60?0:60))};
 const springTicks=S.clockTicks(spring);assert.equal(springTicks.length,46);assert.equal(springTicks.some(t=>t.hour===1),false);
 const autumnStart=Date.parse('2026-10-24T23:00:00Z');
 const autumn={...day,start:autumnStart,end:autumnStart+25*h,samples:Array.from({length:1501},(_,i)=>point(autumnStart+i*m,0,0,i<120?60:0))};
 const autumnTicks=S.clockTicks(autumn);assert.equal(autumnTicks.length,50);assert.equal(autumnTicks.filter(t=>t.major&&t.hour===1).length,2);
});
test('countdown retains seconds and crosses midnight without wrapping',()=>{
 assert.equal(S.countdown(start+28*h,start+23*h+59*m+59000),'04:00:01');
 assert.equal(S.countdown(start+1,start),'00:00:01');
 assert.equal(S.countdown(start,start+1),'00:00:00');
});
test('nearby prayer labels stay separated and anchored to their exact times',()=>{
 const events=[{name:'Maghrib',at:start+18*h},{name:'Isha',at:start+18.2*h}];
 const before=JSON.stringify(events),positions=Layout.labels(day,events,360,360,115,65,35,6);
 assert.ok(Math.abs(positions[1].y-positions[0].y)>=41);
 for(const p of positions){assert.ok(p.x>=0&&p.x+65<=360&&p.y>=0&&p.y+35<=360);assert.equal(p.angle,(p.event.at-day.start)/(day.end-day.start)*2*Math.PI-Math.PI/2)}
 assert.equal(JSON.stringify(events),before);
});
test('timeline keeps clustered prayer labels readable without moving their time markers',()=>{
 const events=[{name:'Dhuhr',at:start+12*h},{name:'Asr',at:start+15*h},{name:'Maghrib',at:start+18*h},{name:'Isha',at:start+18.3*h}];
 const positions=Layout.timeline(day,events,300,68,5);
 assert.ok(positions.some(p=>p.row>0));
 for(const p of positions){
  assert.ok(p.x>=0&&p.x+68<=300);
  assert.equal(p.point,S.fraction(day,p.event.at)*300);
  for(const q of positions)if(q!==p && q.row===p.row)assert.ok(p.x+68+5<=q.x || q.x+68+5<=p.x);
 }
 assert.deepEqual(Layout.timeline(null,events,300,68,5),[]);
});
