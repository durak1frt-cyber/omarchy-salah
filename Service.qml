import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Strings.js" as Strings

Item {
  id: root
  property var shell: null
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("prayer.py").toString().replace(/^file:\/\//, ""))
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/salah"
  property var config: ({})
  property var schedule: null
  property var solarData: null
  property string solarError: ""
  property var earthUsers: []
  readonly property bool earthVisible: earthUsers.length > 0
  readonly property bool solarBusy: solarProc.running
  property bool queuedSolar: false
  property string requestedSolarKey: ""
  property double solarRetryAt: 0
  readonly property string solarLocationKey: {
    var coordinates = null
    if (config.provider === "file") coordinates = schedule ? schedule.coordinates : null
    else if (config.locationMode === "manual" && typeof config.latitude === "number")
      coordinates = {latitude:config.latitude,longitude:config.longitude}
    else if (schedule && schedule.coordinates) coordinates = schedule.coordinates
    if (!coordinates) return ""
    return JSON.stringify({latitude:coordinates.latitude,longitude:coordinates.longitude,
      timezone:config.timezone || (schedule && schedule.timezone) || ""})
  }
  property var memory: ({})
  property bool ready: false
  property bool memoryReady: false
  property bool configReady: false
  property string lastError: ""
  property string errorCode: ""
  property double now: Date.now()
  property double previousTick: 0
  property bool queuedRefresh: false
  property bool queuedForce: false
  property bool lastFetchHadError: false
  property int fetchFailures: 0
  property double nextRefreshAt: 0
  property string previewStage: ""
  property bool refreshAfterConfigure: true
  readonly property string previewPrayerName: "Dhuhr"
  readonly property bool busy: fetchProc.running || configureProc.running
  readonly property var phase: Model.phase(schedule, now, config.beforeMinutes || 0, config.afterMinutes || 0)
  readonly property string visualStage: previewStage || Model.visualStage(phase, memory)
  readonly property string visualPrayerName: previewStage ? previewPrayerName : (phase.prayer ? phase.prayer.name : "")
  readonly property var today: Model.dayAt(schedule, now)
  readonly property string language: config.language || "en"
  signal accentChanged()
  signal configureFailed()
  property string lastVisualStage: "normal"

  function tr(key) { return Strings.text(key, language) }
  function prayerName(name) { return Strings.prayer(name, language) }
  function watchEarth(item, visible) {
    var users = earthUsers.filter(function(u) { return u && u !== item })
    if (visible) users.push(item)
    earthUsers = users
  }
  function refreshSolar() {
    if (!ready || !earthVisible) return
    if (!solarLocationKey) { solarData = null; solarError = "solar_location"; return }
    if (solarProc.running) { queuedSolar = true; return }
    requestedSolarKey = solarLocationKey
    solarProc.command = ["python3", helper.replace(/prayer\.py$/, "solar.py"), "--location", requestedSolarKey, "--state", stateDir]
    solarProc.running = true
  }
  onEarthVisibleChanged: if (earthVisible) refreshSolar()
  onSolarLocationKeyChanged: {
    solarData = null; solarError = ""; solarRetryAt = 0
    if (earthVisible) refreshSolar()
  }
  function start() {
    if (ready || !configReady || !memoryReady) return
    ready = true
    previousTick = Date.now()
    refresh(false)
    refreshSolar()
  }
  function persistMemory() {
    memoryFile.setText(JSON.stringify(memory))
  }
  function acknowledge() {
    if (previewStage) {
      previewStage = ""; previewTimer.stop(); stopAudio(); return
    }
    if (phase.key) {
      memory = Model.remember(memory, "acknowledged", phase.key)
      persistMemory()
    }
    stopAudio()
  }
  function stopAudio() { if (audioProc.running) audioProc.running = false }
  function refresh(force) {
    if (!ready) return
    if (fetchProc.running || configureProc.running) {
      queuedRefresh = true; queuedForce = queuedForce || force; return
    }
    fetchProc.command = ["python3", helper, "schedule"].concat(force ? ["--force"] : [])
    nextRefreshAt = 0
    fetchProc.running = true
  }
  function receiveSchedule(result) {
    lastFetchHadError = !!result.error || !result.days
    if (lastFetchHadError) {
      lastError = result.error || "Could not read the prayer-time response."
      errorCode = result.code || "provider_error"
      fetchFailures = Math.min(fetchFailures + 1, 5)
      nextRefreshAt = errorCode === "setup" ? 0 : Date.now() + Model.retryDelayMs(fetchFailures, result.retryAfterSeconds)
      return
    }
    schedule = result
    lastError = result.warning || ""
    errorCode = ""
    fetchFailures = result.warning ? Math.min(fetchFailures + 1, 5) : 0
    nextRefreshAt = Date.now() + (result.warning ? Model.retryDelayMs(fetchFailures, result.retryAfterSeconds) : 60*60000)
  }
  function configure(next, refreshTimetable) {
    if (busy) return false
    refreshAfterConfigure = refreshTimetable !== false
    configureProc.command = ["python3", helper, "configure", JSON.stringify(next)]
    configureProc.running = true
    return true
  }
  function update(key, value, refreshTimetable) {
    var next = Model.parse(JSON.stringify(config), {})
    next[key] = value
    return configure(next, refreshTimetable)
  }
  function audio(stage) {
    if (config.sound === "off" || audioProc.running) return
    var source = ""
    if (config.sound === "file") {
      // A full adhan belongs at prayer time; pre-prayer alerts get a chime.
      source = stage === "after" ? config.soundFile : ""
    }
    if (!source) source = decodeURIComponent(Qt.resolvedUrl(stage === "before" ? "assets/approaching.wav" : "assets/arrival.wav").toString().replace(/^file:\/\//, ""))
    if (source.charAt(0) !== "/") { lastError = "Choose an absolute path for the audio file."; return }
    audioProc.command = ["pw-play", "--volume", String(config.volume === undefined ? 0.35 : config.volume), source]
    audioProc.running = true
  }
  function notify(p, preview) {
    if (!p.prayer) return
    var title = (preview ? "Salah · Preview" : "Salah") + " · " + prayerName(p.prayer.name)
    var body = p.stage === "after" ? tr("after") + " " + prayerName(p.prayer.name)
      : tr("before") + " · " + Model.remaining(p.prayer.at, now)
    if (preview) body = tr("previewLabel") + "\n" + body
    if (config.notifications && !notifyProc.running) {
      notifyProc.command = ["notify-send", "--app-name=Salah", "--icon=appointment-soon", "--urgency=normal", "--expire-time=10000", "--", title, body]
      notifyProc.running = true
    }
    audio(p.stage)
  }
  function preview(stage) {
    previewStage = stage
    previewTimer.restart()
    notify({stage:stage,prayer:{name:previewPrayerName,at:now+(stage === "before" ? 30*60000 : 0)}}, true)
  }
  function tick() {
    now = Date.now()
    if (!ready) return
    if (Model.shouldNotify(phase, now, previousTick, memory)) {
      memory = Model.remember(memory, "notified", phase.key)
      persistMemory()
      notify(phase, false)
    }
    previousTick = now
    if (earthVisible && !solarBusy && now >= solarRetryAt) {
      var solarDay = Model.dayAt(solarData, now)
      if (solarLocationKey && (!solarData || !solarDay || solarDay.date !== solarData.localDate)) refreshSolar()
    }
    if (nextRefreshAt && now >= nextRefreshAt) {
      nextRefreshAt = now + 5*60000
      refresh(false)
    }
  }
  onVisualStageChanged: {
    if (visualStage !== "normal" && visualStage !== lastVisualStage) accentChanged()
    lastVisualStage = visualStage
  }
  Component.onCompleted: initProc.running = true

  Process {
    id: initProc
    command: ["python3", root.helper, "config"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = Model.parse(text, {})
        if (!result.ok) { root.lastError = result.error || "Could not load settings."; return }
        root.config = result.config
        root.configReady = true
        memoryFile.reload()
        root.start()
      }
    }
  }
  FileView {
    id: memoryFile
    path: root.stateDir + "/reminders.json"
    atomicWrites: true
    printErrors: false
    onLoaded: { root.memory = Model.parse(text(), {}); root.memoryReady = true; root.start() }
    onLoadFailed: { root.memoryReady = true; root.start() }
  }
  Process {
    id: configureProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = Model.parse(text, {})
        if (!result.ok) { root.lastError = result.error || "Could not save settings."; root.configureFailed(); return }
        root.config = result.config
        if (root.refreshAfterConfigure) {
          root.schedule = null
          root.fetchFailures = 0
          root.previousTick = Date.now()
          root.queuedRefresh = true
        }
      }
    }
    onExited: if (root.queuedRefresh) Qt.callLater(function() { root.queuedRefresh = false; root.refresh(false) })
  }
  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = Model.parse(text, {})
        root.receiveSchedule(result)
      }
    }
    onExited: {
      if (root.queuedRefresh) Qt.callLater(function() {
        var force = root.queuedForce
        root.queuedRefresh = false; root.queuedForce = false
        root.refresh(force)
      })
    }
  }
  Process { id: notifyProc }
  Process {
    id: solarProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.requestedSolarKey !== root.solarLocationKey) return
        var result = Model.parse(text, {})
        if (!result.days) { root.solarError = result.code || "solar_error"; root.solarRetryAt = Date.now()+5*60000; return }
        root.solarData = result; root.solarError = ""; root.solarRetryAt = 0
      }
    }
    onExited: if (root.queuedSolar) Qt.callLater(function() { root.queuedSolar = false; root.refreshSolar() })
  }
  Process {
    id: audioProc
    onExited: function(code) { if (code !== 0 && code !== 15) root.lastError = "Audio could not play. Check the file and PipeWire." }
  }
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.tick() }
  Timer { id: previewTimer; interval: 10000; onTriggered: { root.previewStage = ""; root.stopAudio() } }
  IpcHandler {
    target: "salah"
    function status(): string {
      return JSON.stringify({ready:root.ready, busy:root.busy, stage:root.visualStage,
        errorCode:root.errorCode, hasToday:!!root.today, source:root.schedule ? root.schedule.source : "",
        earthVisible:root.earthVisible, solarReady:!!root.solarData, solarBusy:root.solarBusy})
    }
    function refresh(): void { root.refresh(true) }
    function acknowledge(): void { root.acknowledge() }
    function stopAudio(): void { root.stopAudio() }
  }
}
