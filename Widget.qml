import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Strings.js" as Strings

BarWidget {
  id: root
  moduleName: "salah.prayer-times"
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var config: service ? service.config : ({})
  readonly property var phase: service ? service.phase : ({stage:"normal",key:"",next:null,prayer:null,progress:0})
  readonly property string stage: service ? service.visualStage : "normal"
  readonly property color ink: Model.reminderColor(stage, service ? service.visualPrayerName : "", bar ? bar.foreground : Color.foreground)
  readonly property var next: phase.next
  readonly property var barCountdown: service ? Model.barCountdown(phase,service.memory,config,service.now) : null
  readonly property bool dismissed: service && Model.acknowledged(service.memory, phase.key)
  property bool popupOpen: false
  property bool showSettings: false
  readonly property string language: config.language || "en"
  readonly property bool earthMode: config.displayMode !== "classic"
  function tr(key) { return Strings.text(key,language) }
  function name(key) { return Strings.prayer(key,language) }
  function close() { popupOpen = false; showSettings = false }
  function click() {
    if (service) service.acknowledge()
    if (config.clickOpensPanel !== false || !service || !service.today) popupOpen = !popupOpen
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  WidgetButton {
    id: button
    bar: root.bar
    labelVisible: false; hasVisualContent: true
    fixedWidth: root.vertical ? root.barSize : contents.implicitWidth + Style.space(14)
    fixedHeight: root.barSize
    tooltipText: {
      if (!root.service || !root.service.today) return "Salah · " + root.tr("setup")
      if (root.service.previewStage) return root.tr("previewLabel")
      var current = root.phase.prayer
      if (current && !root.dismissed) return root.tr(root.phase.stage) + " " + root.name(current.name) + " · " + current.time
        + (root.barCountdown && root.phase.stage==='after'?'\n'+root.tr('reminderEnds')+' '+root.barCountdown.remaining:'')
      return root.next ? root.name(root.next.name) + " · " + root.next.time + " · " + Model.remaining(root.next.at,root.service.now) : "Salah"
    }
    onPressed: function(button) {
      if (button === Qt.MiddleButton) { if (root.service) root.service.refresh(true) }
      else if (button === Qt.RightButton) root.popupOpen = !root.popupOpen
      else root.click()
    }
    Row {
      id: contents
      anchors.centerIn: parent; spacing: Style.space(7)
      Mosque {
        id: mosque
        width: Math.min(Style.space(15),root.barSize-Style.space(6)); height: width
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Style.space(2)
        ink: root.ink
        motion: root.config.motion !== false && (!root.bar || root.bar.foregroundAnimationEnabled)
      }
      Label {
        objectName:'salah-bar-countdown'
        visible: !!root.barCountdown && !root.vertical && !root.service.previewStage
        anchors.verticalCenter: parent.verticalCenter
        text: root.barCountdown ? root.name(root.barCountdown.name) + " · " + root.barCountdown.remaining : ""
        wrapMode:Text.NoWrap
        color: root.ink; font.pixelSize: Style.font.bodySmall
      }
    }
  }
  Connections { target: root.service; function onAccentChanged() { mosque.pulse() } }

  KeyboardPanel {
    id: panel
    anchorItem: button; owner: root; bar: root.bar; open: root.popupOpen
    focusTarget: viewport
    contentWidth: panel.fittedContentWidth(Style.space(root.earthMode ? 420 : 360))
    contentHeight: panel.fittedContentHeight(Math.min(Style.space(670), body.implicitHeight))
    Flickable {
      id: viewport
      objectName: "salah-popup-content"
      anchors.fill: parent; clip: true
      contentWidth: width; contentHeight: body.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      QQC.ScrollBar.vertical: QQC.ScrollBar { }
      Keys.onEscapePressed: root.close()
      Column {
        id: body
        width: parent.width; spacing: Style.space(14)
        Row {
          width: parent.width; spacing: Style.space(10)
          Column {
            width: parent.width - settingsButton.width - Style.space(10)
            Label { text: "Salah"; font.bold: true; font.pixelSize: Style.font.title }
            Label {
              width: parent.width
              text: root.showSettings ? root.tr("settings") : root.service && root.service.schedule ? root.service.schedule.location : root.tr("setup")
              opacity: 0.65; font.pixelSize: Style.font.caption
            }
          }
          Button {
            id: settingsButton
            objectName: "salah-settings-button"
            iconText: root.showSettings ? "‹" : "⚙"
            iconSize: Style.font.icon
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(5)
            tooltipText: root.tr(root.showSettings ? "back" : "settings")
            Accessible.role: Accessible.Button
            Accessible.name: tooltipText
            focusable: true
            enabled: !!root.service && root.service.configReady
            onClicked: { root.showSettings = !root.showSettings; viewport.contentY = 0 }
          }
        }
        Loader {
          width: parent.width
          active: root.showSettings && !!root.service
          visible: active
          sourceComponent: Component {
            SettingsPane {
              service: root.service
              onSaved: { root.showSettings = false; viewport.contentY = 0 }
            }
          }
        }
        Column {
          width: parent.width; spacing: Style.space(14); visible: !root.showSettings
          Loader {
            id: earthLoader
            width: parent.width
            active: root.popupOpen && !root.showSettings && root.earthMode && !!root.service
            visible: active
            sourceComponent: Component { EarthPanel { objectName: "salah-earth-panel"; service: root.service } }
          }
          Rectangle {
            visible: !root.earthMode
            width: parent.width; height: hero.implicitHeight + Style.space(32)
            radius: Style.space(10)
            color: Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.065)
            border.width: 1; border.color: Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.2)
            Column {
              id: hero
              width: parent.width-Style.space(32); anchors.centerIn: parent; spacing: Style.space(9)
              Label {
                width: parent.width
                text: root.service && root.service.previewStage ? root.tr("previewLabel") : root.dismissed ? root.tr("done")
                  : root.phase.prayer ? root.tr(root.phase.stage) : root.tr("next")
                color: root.ink; font.pixelSize: Style.font.caption
              }
              Label {
                width: parent.width
                text: root.phase.prayer && !root.dismissed ? root.name(root.phase.prayer.name) : root.next ? root.name(root.next.name) : root.tr("setup")
                font.pixelSize: Style.font.displayLarge; font.bold: true
              }
              Label {
                width: parent.width
                text: root.phase.stage === "after" && !root.dismissed ? root.phase.prayer.time
                  : root.next && root.service ? Model.remaining(root.next.at,root.service.now) + " · " + root.next.time : root.tr("setupBody")
                opacity: 0.7
              }
              Button {
                visible: !!root.phase.key && !root.dismissed
                text: root.tr("dismiss"); bordered: true; focusable: true
                onClicked: if (root.service) root.service.acknowledge()
              }
            }
          }
          Row {
            width: parent.width; visible: !!root.service && !!root.service.today
            Label { width: parent.width/2; text: root.tr("today"); font.bold: true }
            Label { width: parent.width/2; horizontalAlignment: Text.AlignRight; text: root.service && root.service.today ? root.service.today.date : ""; opacity: 0.6; font.pixelSize: Style.font.caption }
          }
          Column {
            width: parent.width; spacing: Style.space(3)
            Repeater {
              model: root.service && root.service.today ? root.service.today.events : []
              Rectangle {
                required property var modelData
                readonly property bool upcoming: root.next && root.next.name === modelData.name && root.next.at === modelData.at
                width: parent.width; height: Style.space(39); radius: Style.space(5)
                color: upcoming ? Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.08) : "transparent"
                Row {
                  anchors.fill: parent; anchors.margins: Style.space(8)
                  Label { width: parent.width*0.62; text: root.name(modelData.name); font.bold: upcoming; opacity: modelData.name === "Sunrise" ? 0.55 : 1 }
                  Label { width: parent.width*0.38; text: modelData.time; horizontalAlignment: Text.AlignRight; font.bold: upcoming; opacity: modelData.name === "Sunrise" ? 0.55 : 1 }
                }
              }
            }
          }
          Label {
            width: parent.width; visible: !!root.service && !!root.service.lastError
            text: root.service ? root.service.lastError : ""; color: "#ee7474"; font.pixelSize: Style.font.caption
          }
          Label {
            width: parent.width
            visible: !!root.service && !!root.service.schedule && !root.service.today
            text: root.tr("expired"); color: "#ee7474"; font.pixelSize: Style.font.caption
          }
          Label {
            width: parent.width; visible: !!root.service && !!root.service.schedule
            text: root.service && root.service.schedule ? root.tr(root.service.schedule.source === "file" ? "local" : "source") + " · " + root.service.schedule.timezone : ""
            font.pixelSize: Style.font.caption; opacity: 0.55
          }
          Row {
            spacing: Style.space(6)
            Button { text: root.tr("refresh"); bordered: true; focusable: true; enabled: !!root.service && !root.service.busy; onClicked: root.service.refresh(true) }
            Button { text: root.tr("stop"); focusable: true; onClicked: if (root.service) root.service.stopAudio() }
            Button { text: root.tr("dismiss"); visible: root.earthMode && !!root.phase.key && !root.dismissed; focusable: true; onClicked: if(root.service)root.service.acknowledge() }
          }
          PanelSeparator { width: parent.width }
          Label { width: parent.width; text: root.tr("preview"); font.bold: true; font.pixelSize: Style.font.bodySmall }
          Row {
            spacing: Style.space(6)
            Button { text: root.tr("before"); foreground: Model.reminderColor("before", root.service ? root.service.previewPrayerName : "Dhuhr", Color.foreground); bordered: true; focusable: true; onClicked: if (root.service) root.service.preview("before") }
            Button { text: root.tr("after"); foreground: "#65c98b"; bordered: true; focusable: true; onClicked: if (root.service) root.service.preview("after") }
          }
          Label { width: parent.width; text: root.tr("ring"); opacity: 0.6; font.pixelSize: Style.font.caption }
          Label { width: parent.width; text: root.tr("hint"); opacity: 0.6; font.pixelSize: Style.font.caption }
        }
      }
    }
  }
}
