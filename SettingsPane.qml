import QtQuick
import qs.Ui
import qs.Commons
import "Strings.js" as Strings
import "Qibla.js" as Qibla

Column {
  id: root
  objectName: 'salah-settings-pane'
  required property var service
  property var draft: ({})
  property bool saving: false
  readonly property var qiblaCoordinates: Qibla.coordinates(draft,service.config,service.schedule)
  readonly property var qiblaBearing: Qibla.bearing(qiblaCoordinates)
  signal saved()
  spacing: Style.space(12)
  function tr(key) { return Strings.text(key, draft.language || "en") }
  function reset() { draft = JSON.parse(JSON.stringify(service.config)) }
  function set(key, value) {
    var next = JSON.parse(JSON.stringify(draft)); next[key] = value; draft = next
  }
  Component.onCompleted: reset()
  Connections {
    target: root.service
    function onConfigChanged() {
      for(var key of ['showQibla','countdown','countdownWindow','locationMode'])root.set(key,root.service.config[key])
      if (root.saving) { root.saving = false; root.saved() }
    }
    function onConfigureFailed() { root.saving = false }
  }
  Dropdown {
    width: parent.width; label: root.tr("language"); value: root.draft.language || "en"
    options: [{value:"en",label:"English"},{value:"tr",label:"Türkçe"},{value:"ar",label:"العربية"}]
    onChanged: function(value) { root.set("language",value) }
  }
  Dropdown {
    width: parent.width; label: root.tr("provider"); value: root.draft.provider || "aladhan"
    options: [{value:"aladhan",label:"AlAdhan"},{value:"file",label:root.tr("local")}]
    onChanged: function(value) { root.set("provider",value) }
  }
  Dropdown {
    width: parent.width; label: root.tr("displayMode"); value: root.draft.displayMode || "earth"
    options: [{value:"earth",label:root.tr("earth")},{value:"classic",label:root.tr("classic")}]
    onChanged: function(value) { root.set("displayMode",value) }
  }
  Dropdown {
    width: parent.width; label: root.tr("guidanceProfile"); value: root.draft.guidanceProfile || "diyanet"
    options: [{value:"diyanet",label:root.tr("diyanetGuidance")},{value:"off",label:root.tr("guidanceOff")}]
    onChanged: function(value) { root.set("guidanceProfile",value) }
  }
  Column {
    width:parent.width;spacing:Style.space(6)
    Label {width:parent.width;text:root.tr('qibla');font.pixelSize:Style.font.caption;opacity:0.75}
    Label {
      objectName:'salah-qibla-bearing';width:parent.width
      text:typeof root.qiblaBearing==='number'?root.qiblaBearing.toFixed(1)+'° · '+root.tr('trueNorth'):root.tr(root.qiblaCoordinates?'qiblaUndefined':'qiblaUnavailable')
      font.pixelSize:Style.font.bodySmall
    }
    Toggle {
      objectName:'salah-qibla-toggle';width:parent.width;label:root.tr('showQibla');titleSize:Style.font.bodySmall
      description:root.tr('showQiblaHint');checked:root.service.config.showQibla===true
      enabled:root.service.configReady && !root.service.busy
      onClicked:if(enabled)root.service.update('showQibla',!checked,false)
    }
  }
  Column {
    width: parent.width; spacing: Style.space(8); visible: root.draft.provider !== "file"
    Toggle {
      objectName:'salah-auto-location-toggle'
      width: parent.width; label: root.tr("autoLocation"); titleSize: Style.font.bodySmall
      checked: root.service.config.locationMode !== "manual"
      description: root.tr("autoLocationHint")
      enabled:root.service.configReady && !root.service.busy
      onClicked:if(enabled)root.service.update('locationMode',checked?'manual':'auto',true)
    }
    Label {
      visible: root.draft.locationMode !== "manual" && !!root.service.schedule && root.service.schedule.locationMode === "auto"
      width: parent.width; font.pixelSize: Style.font.caption
      text: root.service.schedule ? root.service.schedule.location : ""
    }
    Column {
      width: parent.width; spacing: Style.space(8); visible: root.draft.locationMode === "manual"
      Label { text: root.tr("city"); width: parent.width; font.pixelSize: Style.font.caption }
      TextField { width: parent.width; text: root.draft.city || ""; placeholderText: root.tr("city"); onTextEdited: { root.set("latitude",null); root.set("longitude",null); root.set("city",text) } }
      Label { text: root.tr("country"); width: parent.width; font.pixelSize: Style.font.caption }
      TextField { width: parent.width; text: root.draft.country || ""; placeholderText: root.tr("country"); onTextEdited: { root.set("latitude",null); root.set("longitude",null); root.set("country",text) } }
      Label {
        width: parent.width; font.pixelSize: Style.font.caption
        visible: root.draft.latitude !== undefined && root.draft.latitude !== null
        text: root.tr("coordinates") + ": " + root.draft.latitude + ", " + root.draft.longitude + "\n" + root.tr("coordinatesHint")
      }
    }
    Dropdown {
      width: parent.width; label: root.tr("method"); value: String(root.draft.method === undefined ? 3 : root.draft.method)
      options: Strings.methods
      onChanged: function(value) { root.set("method",Number(value)) }
    }
    Dropdown {
      width: parent.width; label: root.tr("school"); value: String(root.draft.school || 0)
      options: [{value:"0",label:"Standard (Shafi‘i, Maliki, Hanbali)"},{value:"1",label:"Hanafi"}]
      onChanged: function(value) { root.set("school",Number(value)) }
    }
  }
  Column {
    width: parent.width; spacing: Style.space(6); visible: root.draft.provider === "file"
    Label { text: root.tr("filePath"); width: parent.width; font.pixelSize: Style.font.caption }
    TextField { width: parent.width; text: root.draft.scheduleFile || ""; onTextEdited: root.set("scheduleFile",text) }
  }
  NumberField {
    label: root.tr("beforeWindow"); value: root.draft.beforeMinutes === undefined ? 30 : root.draft.beforeMinutes
    from: 0; to: 120; onModified: function(value) { root.set("beforeMinutes",value) }
  }
  NumberField {
    label: root.tr("afterWindow"); value: root.draft.afterMinutes === undefined ? 30 : root.draft.afterMinutes
    from: 0; to: 120; onModified: function(value) { root.set("afterMinutes",value) }
  }
  Repeater {
    model: [{key:"notifications",label:"notifications"},{key:"motion",label:"motion"},
      {key:"countdown",label:"countdown"},{key:"clickOpensPanel",label:"acknowledgeOpen"}]
    Toggle {
      required property var modelData
      objectName:'salah-'+modelData.key+'-toggle'
      width: root.width; label: root.tr(modelData.label)
      titleSize: Style.font.bodySmall
      checked: modelData.key==='countdown'?!!root.service.config.countdown:!!root.draft[modelData.key]
      enabled:modelData.key!=='countdown'||(root.service.configReady && !root.service.busy)
      description:modelData.key==='countdown'?root.tr('countdownHint'):''
      onClicked:if(enabled){if(modelData.key==='countdown')root.service.update('countdown',!checked,false);else root.set(modelData.key,!checked)}
    }
  }
  Dropdown {
    objectName:'salah-countdown-window';width:parent.width;visible:!!root.service.config.countdown
    label:root.tr('countdownWindow');value:root.service.config.countdownWindow||'both'
    enabled:root.service.configReady && !root.service.busy
    options:[{value:'both',label:root.tr('countdownBoth')},{value:'before',label:root.tr('countdownBefore')},{value:'after',label:root.tr('countdownAfter')}]
    onChanged:function(value){if(enabled)root.service.update('countdownWindow',value,false)}
  }
  Dropdown {
    width: parent.width; label: root.tr("sound"); value: root.draft.sound || "off"
    options: [{value:"off",label:"Silent"},{value:"chime",label:"Soft chimes"},{value:"file",label:"My adhan / audio file"}]
    onChanged: function(value) { root.set("sound",value) }
  }
  Column {
    width: parent.width; spacing: Style.space(6); visible: root.draft.sound === "file"
    Label { text: root.tr("soundFile"); width: parent.width; font.pixelSize: Style.font.caption }
    TextField { width: parent.width; text: root.draft.soundFile || ""; onTextEdited: root.set("soundFile",text) }
  }
  NumberField {
    visible: root.draft.sound !== "off"; label: "Volume %"; from: 0; to: 100
    value: Math.round((root.draft.volume === undefined ? 0.35 : root.draft.volume)*100)
    onModified: function(value) { root.set("volume",value/100) }
  }
  Label {
    width: parent.width; visible: root.draft.provider !== "file"
    text: root.tr(root.draft.locationMode !== "manual" ? "autoPermission"
      : root.draft.latitude !== undefined && root.draft.latitude !== null ? "coordinatePermission" : "permission")
    font.pixelSize: Style.font.caption; opacity: 0.75
  }
  Label {
    width: parent.width; visible: !!root.service.lastError
    text: root.service.lastError; color: "#e57373"; font.pixelSize: Style.font.caption
  }
  Button {
    width: parent.width; text: root.service.busy ? "…" : root.tr(root.draft.provider === "file" ? "importSave" : "save")
    bordered: true; focusable: true; enabled: !root.service.busy
    onClicked: { root.saving = root.service.configure(root.draft) }
  }
}
