import QtQuick
import Quickshell
import "./plugin" as Salah
ShellRoot {
  id: harness
  function findNamed(item, name) {
    if (item.objectName === name) return item
    var children = item.data || item.children || []
    for (var i=0; i<children.length; i++) { var found=findNamed(children[i], name); if (found) return found }
    if (item.contentItem) return findNamed(item.contentItem, name)
    return null
  }
  Salah.Service { id: service }
  QtObject {
    id: fakeBar
    property var shell: QtObject { function serviceFor(id) { return service } }
    property color foreground: "#d9e2e8"
    property color barForeground: foreground
    property color background: "#121820"
    property color urgent: "#ee7474"
    property string fontFamily: "sans-serif"
    property string position: "top"
    property bool vertical: false
    property int barSize: 38
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    function showTooltip(target,text) {}
    function hideTooltip(target) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function requestPopout(target) {}
    function releasePopout(target) {}
    function targetBelongsToWindow(target) { return true }
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 800; implicitHeight: 700
    color: "#121820"
    Rectangle { id: capture; anchors.fill: parent; color: "#121820"
    Salah.Widget { id: first; bar: fakeBar; x:30; y:20 }
    Salah.Widget { id: second; bar: fakeBar; x:100; y:20 }
    Salah.SettingsPane { id: settings; service: service; width:360; x:200; y:70; visible:false }
  }
  }
  property int step: 0
  property bool settingsCaptured:false
  property var qiblaSchedule:null
  Timer {
    interval: 700; running:true; repeat:true
    onTriggered: {
      if (!service.ready || service.busy) return
      function check(value,label) { if (!value) { console.error("FAIL: " + label); Qt.quit(); throw new Error(label) } }
      if (step === 0) {
        check(service.errorCode === "setup", "first-run setup")
        service.lastError = ""
        service.config = Object.assign({},service.config,{notifications:false,sound:"off",clickOpensPanel:false})
        var now=Date.now()
        service.schedule = {identity:"qml-fixture", location:"Test fixture",timezone:"UTC",source:"file", days:[{date:"fixture", start:now-86400000,end:now+86400000,events:[{name:"Dhuhr",at:now+900000,time:"12:00"}]}]}
      } else if (step === 1) {
        check(first.stage === "before" && second.stage === "before", "both monitors approaching")
        check(first.ink.toString() === "#e9c46a" && second.ink.toString() === "#e9c46a", "yellow before Dhuhr on both monitors")
        var saved=service.schedule
        for (var prayer of ["Fajr","Asr","Maghrib","Isha"]) {
          var fixture=JSON.parse(JSON.stringify(saved))
          fixture.days[0].events[0].name=prayer
          service.schedule=fixture
          check(first.ink.toString() === (prayer === "Fajr" ? "#e9c46a" : "#ee7474"), "approaching colour for " + prayer)
        }
        service.preview("before")
        check(first.ink.toString() === "#e9c46a", "Dhuhr preview stays yellow while live Isha is red")
        service.acknowledge()
        check(first.ink.toString() === "#ee7474", "ending preview restores live Isha red")
        service.schedule=saved
        first.click()
      } else if (step === 2) {
        check(first.stage === "normal" && second.stage === "normal", "acknowledgement shared")
        check(first.ink.toString() === fakeBar.foreground.toString(), "dismissal restores theme colour")
        var now=Date.now()
        service.schedule = {identity:"qml-fixture",location:"Test fixture",timezone:"UTC",source:"file",days:[{date:"fixture",start:now-86400000,end:now+86400000,events:[{name:"Dhuhr",at:now-900000,time:"12:00"}]}]}
      } else if (step === 3) {
        check(first.stage === "after" && second.stage === "after", "green after prayer")
        check(first.ink.toString() === "#65c98b", "green colour")
        first.popupOpen=true
        settings.reset()
      } else if (step === 4) {
        
        function find(item) {
          if (item.objectName === "salah-popup-content") return item
          var children = item.data || item.children || []
          for (var i=0;i<children.length;i++) { var found=find(children[i]); if (found) return found }
          if (item.contentItem) return find(item.contentItem)
          return null
        }
        var content = find(first)
        check(!!content,"popup content can be rendered")
        content.grabToImage(function(result) { result.saveToFile("SCREENSHOT_PATH") })
        console.log("PASS: service, first-run setup, yellow/red/green, preview isolation, shared acknowledgement, settings")
      } else if (step === 5) {
        service.config=Object.assign({},service.config,{latitude:41.0082,longitude:28.9784})
        settings.reset()
        var gear=harness.findNamed(first,"salah-settings-button")
        check(!!gear && gear.text === "" && gear.iconText === "⚙", "small settings gear")
        gear.clicked()
        check(first.showSettings,"gear opens settings")
      } else if (step === 6) {
        var liveSettings=harness.findNamed(first,'salah-settings-pane')
        check(!!liveSettings && Math.abs(liveSettings.qiblaBearing-151.6)<.1,'live settings show the selected location bearing')
        liveSettings.grabToImage(function(result){result.saveToFile('SETTINGS_SCREENSHOT_PATH');harness.settingsCaptured=true})
        check(Math.abs(settings.qiblaBearing-151.6)<.1,'settings automatically show qibla degrees')
        var qiblaToggle=harness.findNamed(liveSettings,'salah-qibla-toggle')
        check(!qiblaToggle.checked,'qibla starts off')
        settings.set('latitude',null);settings.set('longitude',null);settings.set('city','New location')
        check(settings.qiblaBearing===null,'editing location hides the old bearing')
        var saved=service.schedule
        service.fetchFailures=0
        var started=Date.now()
        service.receiveSchedule({error:"AlAdhan temporarily unavailable (HTTP 503)",code:"provider_unavailable",retryAfterSeconds:600})
        check(service.schedule === saved,"503 preserves the timetable")
        check(service.errorCode === "provider_unavailable","503 classified as an outage")
        check(service.nextRefreshAt >= started+600000,"server retry delay respected")
        service.receiveSchedule(saved)
        check(service.errorCode === "" && service.fetchFailures === 0,"successful fetch clears outage state")
      } else if (step === 7) {
        if(!harness.settingsCaptured)return
        var liveSettings=harness.findNamed(first,'salah-settings-pane')
        liveSettings.set('city','Unsaved city draft')
        harness.qiblaSchedule=service.schedule
        harness.findNamed(liveSettings,'salah-qibla-toggle').clicked()
        harness.findNamed(first,'salah-settings-button').clicked()
        check(!first.showSettings,'leave settings immediately after toggling Qibla')
      } else if (step === 8) {
        harness.findNamed(first,'salah-settings-button').clicked()
      } else if (step === 9) {
        var reopened=harness.findNamed(first,'salah-settings-pane')
        check(harness.findNamed(reopened,'salah-qibla-toggle').checked,'Qibla stays enabled after leaving and reopening settings')
        check(service.config.showQibla===true,'Qibla saves without the bottom Save button')
        check(service.config.city!=='Unsaved city draft','Qibla does not save unrelated draft edits')
        check(service.schedule===harness.qiblaSchedule,'Qibla preserves the loaded timetable without a refresh')
        reopened.set('city','Keep this draft')
        harness.findNamed(reopened,'salah-qibla-toggle').clicked()
      } else if (step === 10) {
        var reopened=harness.findNamed(first,'salah-settings-pane')
        check(first.showSettings && !harness.findNamed(reopened,'salah-qibla-toggle').checked,'switching Qibla off saves and keeps settings open')
        check(!service.config.showQibla && reopened.draft.showQibla===false,'saved Qibla value stays synchronized with the draft')
        check(reopened.draft.city==='Keep this draft','immediate save preserves unfinished draft edits')
        harness.findNamed(reopened,'salah-qibla-toggle').clicked()
        first.close()
      } else if (step === 11) {
        check(service.config.showQibla===true,'Qibla saves even when the popup is closed immediately')
        console.log("PASS: popup opens and settings loads")
        first.close()
        Qt.quit()
      }
      step++
    }
  }
}
