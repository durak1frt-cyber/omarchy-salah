// Pure time/state logic shared by QML and the regression tests.
var PRAYERS = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
var ORDER = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

function parse(raw, fallback) {
  try { return JSON.parse(raw) || fallback } catch (_) { return fallback }
}

function retryDelayMs(failures, retryAfterSeconds) {
  var delay = Math.min(15, Math.pow(2, Math.max(0, Math.min(4, failures - 1)))) * 60000
  if (typeof retryAfterSeconds === "number" && isFinite(retryAfterSeconds) && retryAfterSeconds >= 0)
    delay = Math.max(delay, retryAfterSeconds * 1000)
  return delay
}

function events(schedule) {
  return ((schedule && schedule.days) || []).reduce(function(all, day) {
    return all.concat((day.events || []).filter(function(e) {
      return PRAYERS.indexOf(e.name) >= 0 && typeof e.at === "number" && isFinite(e.at)
    }))
  }, []).sort(function(a, b) { return a.at - b.at })
}

function phase(schedule, now, beforeMinutes, afterMinutes) {
  var list = events(schedule)
  var previous = null
  var next = null
  for (var i = 0; i < list.length; i++) {
    if (list[i].at <= now) previous = list[i]
    else { next = list[i]; break }
  }
  // The prayer that just began takes priority when two windows overlap.
  var current = null
  var stage = "normal"
  var start = 0
  var end = 0
  if (previous && now < previous.at + afterMinutes * 60000) {
    current = previous; stage = "after"
    start = current.at; end = current.at + afterMinutes * 60000
  } else if (next && now >= next.at - beforeMinutes * 60000) {
    current = next; stage = "before"
    start = current.at - beforeMinutes * 60000; end = current.at
  }
  return {
    stage: stage, prayer: current, next: next, previous: previous,
    start: start, end: end,
    progress: current && end > start ? Math.max(0, Math.min(1, (now - start) / (end - start))) : 0,
    key: current ? schedule.identity + ":" + current.name + ":" + current.at + ":" + stage : ""
  }
}

function acknowledged(state, key) {
  return !!key && ((state && state.acknowledged) || []).indexOf(key) >= 0
}

function visualStage(p, state) {
  return acknowledged(state, p.key) ? "normal" : p.stage
}

function reminderColor(stage, prayerName, normalColor) {
  if (stage === "after") return "#65c98b"
  if (stage === "before")
    return prayerName === "Fajr" || prayerName === "Dhuhr" ? "#e9c46a" : "#ee7474"
  return normalColor
}

function barCountdown(p, state, config, now) {
  if(!config.countdown || !p.prayer || p.stage==='normal' || acknowledged(state,p.key))return null
  var window=config.countdownWindow||'both'
  if(window!=='both' && window!==p.stage)return null
  var end=p.stage==='before'?p.prayer.at:p.end
  if(now>=end)return null
  return {name:p.prayer.name,stage:p.stage,remaining:remaining(end,now)}
}

function remember(state, field, key) {
  var copy = parse(JSON.stringify(state || {}), {})
  var list = (copy[field] || []).filter(function(k) { return k !== key })
  if (key) list.push(key)
  copy[field] = list.slice(-96)
  return copy
}

function shouldNotify(p, now, previousTick, state) {
  if (!p.key || acknowledged(state, p.key)) return false
  if (((state && state.notified) || []).indexOf(p.key) >= 0) return false
  // No notification burst on startup, waking a laptop, or a clock jump.
  return previousTick > 0 && now >= previousTick && now - previousTick <= 90000
    && p.start > previousTick && p.start <= now
}

function remaining(at, now) {
  var minutes = Math.max(0, Math.ceil((at - now) / 60000))
  return minutes >= 60 ? Math.floor(minutes / 60) + "h " + minutes % 60 + "m" : minutes + "m"
}

function dayAt(schedule, now) {
  var days = (schedule && schedule.days) || []
  for (var i = 0; i < days.length; i++) {
    if (now >= days[i].start && now < days[i].end) return days[i]
  }
  return null
}

if (typeof module !== "undefined") module.exports = {
  PRAYERS: PRAYERS, ORDER: ORDER, parse: parse, events: events, phase: phase,
  acknowledged: acknowledged, visualStage: visualStage, reminderColor: reminderColor, remember: remember,
  shouldNotify: shouldNotify, remaining: remaining, dayAt: dayAt, retryDelayMs: retryDelayMs, barCountdown: barCountdown
}
