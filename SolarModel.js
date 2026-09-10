// Pure display calculations. No notification or acknowledgement state is touched here.
var GUIDANCE_SOURCE = "https://kurul.diyanet.gov.tr/tr/fetva/mekruh-vakitler-hangileridir-hangi-vakitlerde-kaza-ve-hangi/0193c42d-52b7-7186-d5b4-f1d3c950ad73"
var minute = 60000
function dayAt(solar, at) {
  var days=(solar && solar.days)||[]
  for (var i=0;i<days.length;i++) if (at>=days[i].start && at<days[i].end) return days[i]
  return null
}
function position(day,at) {
  if (!day || !day.samples || !day.samples.length) return null
  var samples=day.samples, i=Math.max(0,Math.min(samples.length-2,Math.floor((at-day.start)/minute)))
  var a=samples[i],b=samples[i+1],t=Math.max(0,Math.min(1,(at-a[0])/(b[0]-a[0])))
  var xyz=[1,2,3].map(function(k){return a[k]+t*(b[k]-a[k])})
  var norm=Math.sqrt(xyz.reduce(function(n,v){return n+v*v},0))
  var da=((b[5]-a[5]+540)%360)-180
  return {vector:xyz.map(function(v){return v/norm}),altitude:a[4]+t*(b[4]-a[4]),azimuth:(a[5]+t*da+360)%360,offset:t===1?b[6]:a[6]}
}
function clock(day,at) {
  var p=position(day,at); if (!p) return "—"
  var d=new Date(at+(p.offset||0)*minute)
  return String(d.getUTCHours()).padStart(2,"0")+":"+String(d.getUTCMinutes()).padStart(2,"0")
}
function offsetLabel(day,at) {
  var p=position(day,at), offset=p ? p.offset||0:0
  return "UTC"+(offset>=0?"+":"−")+Math.floor(Math.abs(offset)/60)+":"+String(Math.abs(offset)%60).padStart(2,"0")
}
function clockTicks(day) {
  if(!day)return []
  // Inspect local wall time so half-hour marks survive DST and fractional offsets.
  return day.samples.filter(function(s){return s[0]<day.end && (s[0]+s[6]*minute)%(30*minute)===0})
    .map(function(s){var d=new Date(s[0]+s[6]*minute);return {at:s[0],major:d.getUTCMinutes()===0,hour:d.getUTCHours()}})
}
function countdown(target,at) {
  var seconds=Math.max(0,Math.ceil((target-at)/1000))
  return [Math.floor(seconds/3600),Math.floor(seconds/60)%60,seconds%60]
    .map(function(n){return String(n).padStart(2,'0')}).join(':')
}
function phaseName(alt) {
  return alt>=0?"daylight":alt>=-6?"civilTwilight":alt>=-12?"nauticalTwilight":alt>=-18?"astronomicalTwilight":"night"
}
function segment(kind,name,start,end,extra) {
  var s={id:kind+":"+name+":"+start,kind:kind,name:name,start:start,end:end,estimated:false}
  Object.keys(extra||{}).forEach(function(k){s[k]=extra[k]}); return s
}
function build(day,schedule,enabled) {
  var result={prayer:[],solar:[],guidance:[],guidanceUnavailable:false}
  if (!day) return result
  var events=[]
  ;((schedule && schedule.days)||[]).forEach(function(d){(d.events||[]).forEach(function(e){events.push({name:e.name,at:e.at,dayStart:d.start,dayEnd:d.end})})})
  events.sort(function(a,b){return a.at-b.at})
  var seen={};events=events.filter(function(e){var k=e.name+e.at;if(seen[k])return false;seen[k]=true;return true})
  for (var i=0;i<events.length;i++) {
    var event=events[i],end=i+1<events.length?events[i+1].at:Math.min(day.end,event.dayEnd||event.at)
    // A missing next day must not stretch yesterday's Isha across an uncached day.
    if (event.dayEnd && events[i+1] && events[i+1].dayStart>event.dayEnd) end=Math.min(end,event.dayEnd)
    if (end<=day.start || event.at>=day.end)continue
    result.prayer.push(segment("prayer",event.name==="Sunrise"?"morning":event.name,Math.max(day.start,event.at),Math.min(day.end,end),{boundaryStart:event.at,boundaryEnd:i+1<events.length?end:null}))
  }
  var transitions=[['astronomicalDawn','astronomicalTwilight'],['nauticalDawn','nauticalTwilight'],['civilDawn','civilTwilight'],['sunrise','daylight'],['sunset','civilTwilight'],['civilDusk','nauticalTwilight'],['nauticalDusk','astronomicalTwilight'],['astronomicalDusk','night']]
    .filter(function(e){return typeof day.events[e[0]]==='number'})
    .map(function(e){return {at:day.events[e[0]],name:e[1]}}).sort(function(a,b){return a.at-b.at})
  var begin=day.start, name=phaseName(day.samples[0][4])
  transitions.forEach(function(e){if(e.at>begin)result.solar.push(segment('solar',name,begin,e.at));begin=e.at;name=e.name})
  if(begin<day.end)result.solar.push(segment('solar',name,begin,day.end))
  if(enabled) {
    var dhuhr=events.filter(function(e){return e.name==='Dhuhr' && e.at>=day.start && e.at<day.end})[0]
    var rise=day.events.sunrise,set=day.events.sunset
    if(day.regime==='normal' && typeof rise==='number' && typeof set==='number' && dhuhr) {
      var intervals=[segment('guidance','sunriseGuidance',rise,rise+45*minute),segment('guidance','noonGuidance',dhuhr.at-10*minute,dhuhr.at),segment('guidance','sunsetGuidance',set-45*minute,set)]
      var valid=intervals.every(function(s,i){return s.start>=day.start && s.end<=day.end && s.start<s.end && (!i||intervals[i-1].end<=s.start)})
      if(valid) result.guidance=intervals.map(function(s){s.estimated=true;s.source=GUIDANCE_SOURCE;return s})
      else result.guidanceUnavailable=true
    } else result.guidanceUnavailable=true
  }
  return result
}
function active(list,at) {return (list||[]).filter(function(s){return s.start<=at && at<s.end})[0]||null}
function fraction(day,at) {return Math.max(0,Math.min(1,(at-day.start)/(day.end-day.start)))}
function atFraction(day,fraction) {return Math.min(day.end-1,day.start+Math.max(0,Math.min(1,fraction))*(day.end-day.start))}
function camera(lat,lon) {
  var p=lat*Math.PI/180,l=lon*Math.PI/180
  return {front:[Math.cos(p)*Math.cos(l),Math.cos(p)*Math.sin(l),Math.sin(p)],east:[-Math.sin(l),Math.cos(l),0],north:[-Math.sin(p)*Math.cos(l),-Math.sin(p)*Math.sin(l),Math.cos(p)]}
}
function colour(s) {
  var colors={Fajr:'#988EA9',morning:'#B4AC7D',Dhuhr:'#D1BD79',Asr:'#BBA078',Maghrib:'#A17F8E',Isha:'#7D8CAF',daylight:'#F2C66D',civilTwilight:'#CBA583',nauticalTwilight:'#827DAB',astronomicalTwilight:'#58688E',night:'#3C526F'}
  return s.kind==='guidance'?'#D99B45':colors[s.name]||'#819887'
}
if(typeof module!=="undefined")module.exports={dayAt:dayAt,position:position,clock:clock,offsetLabel:offsetLabel,clockTicks:clockTicks,countdown:countdown,phaseName:phaseName,build:build,active:active,fraction:fraction,atFraction:atFraction,camera:camera,colour:colour,GUIDANCE_SOURCE:GUIDANCE_SOURCE}
