import QtQuick
import qs.Ui
import qs.Commons
import "SolarModel.js" as Solar
import "EarthStrings.js" as EarthText
import "Strings.js" as Strings
import "Model.js" as Model

Column {
  id: root
  required property var service
  property bool forceFallback: false
  property bool previewing: false
  property double previewAt: 0
  property string selectedId: ""
  readonly property string language: service.language || "en"
  readonly property var day: Solar.dayAt(service.solarData,service.now)
  readonly property double displayAt: previewing && day ? Math.max(day.start,Math.min(day.end-1,previewAt)) : service.now
  readonly property var position: Solar.position(day,displayAt)
  readonly property bool rising: !!position && Solar.position(day,Math.min(day.end,displayAt+60000)).altitude >= position.altitude
  readonly property var intervals: Solar.build(day,service.schedule,service.config.guidanceProfile === "diyanet")
  readonly property var choices: intervals.prayer.concat(intervals.solar,intervals.guidance)
  readonly property var prayer: Solar.active(intervals.prayer,displayAt)
  readonly property var solarPhase: Solar.active(intervals.solar,displayAt)
  readonly property var guidance: Solar.active(intervals.guidance,displayAt)
  readonly property var prayerEvents: Model.events(service.schedule)
  readonly property var dialPrayers: day?prayerEvents.filter(function(p){return p.at>=root.day.start && p.at<root.day.end}):[]
  readonly property var nextPrayer: prayerEvents.filter(function(p){return p.at>root.displayAt})[0] || null
  readonly property string remaining: nextPrayer?Solar.countdown(nextPrayer.at,displayAt):""
  readonly property color goldText: Color.foreground.r+Color.foreground.g+Color.foreground.b>1.5?"#F2C66D":"#895A10"
  readonly property var selectedInterval: choices.filter(function(s){return s.id===root.selectedId})[0] || guidance || prayer || solarPhase
  function tr(key) {return EarthText.text(key,language)}
  function name(key) {return ['Fajr','Dhuhr','Asr','Maghrib','Isha'].indexOf(key)>=0?Strings.prayer(key,language):tr(key)}
  function time(at) {return day && typeof at==='number'?Solar.clock(day,at):'—'}
  function preview(fraction) {if(!day)return;previewAt=Solar.atFraction(day,fraction);previewing=true;selectedId=''}
  function live() {previewing=false;selectedId=''}
  spacing: Style.space(12)
  LayoutMirroring.enabled: language === 'ar'
  LayoutMirroring.childrenInherit: true
  Component.onCompleted: service.watchEarth(root,true)
  Component.onDestruction: if(service)service.watchEarth(root,false)
  onDayChanged: if(previewing && day && (previewAt<day.start || previewAt>=day.end))live()

  Label {
    width:parent.width;visible:!root.day
    text:root.service.solarBusy?root.tr('loading'):root.tr(root.service.solarLocationKey?'unavailable':'coordinatesNeeded')
    font.pixelSize:Style.font.bodySmall
  }
  Column {
    width:parent.width;spacing:Style.space(12);visible:!!root.day
    Row {
      width:parent.width
      LayoutMirroring.enabled:false
      Label {width:parent.width*0.65;text:root.day?root.day.date+' · '+Solar.offsetLabel(root.day,root.displayAt):'';opacity:0.65;font.pixelSize:Style.font.caption}
      Label {width:parent.width*0.35;text:root.tr(root.previewing?'preview':'live');color:root.previewing?'#F2C66D':Color.foreground;horizontalAlignment:Text.AlignRight;font.pixelSize:Style.font.caption}
    }
    Item {
      width:parent.width;height:width
      LayoutMirroring.enabled:false
      EarthGlobe {
        id:globe;objectName:'salah-earth-globe';anchors.centerIn:parent;width:Math.max(100,(dial.radius-Style.space(18))*2);height:width
        latitude:root.service.solarData?root.service.solarData.location.latitude:0
        longitude:root.service.solarData?root.service.solarData.location.longitude:0
        sun:root.position?root.position.vector:[1,0,0]
        forceFallback:root.forceFallback
        showQibla:root.service.config.showQibla===true;language:root.language
      }
      IntervalDial {
        id:dial;objectName:'salah-interval-dial';anchors.fill:parent
        day:root.day;intervals:root.intervals;at:root.displayAt;foreground:Color.foreground
        prayerEvents:root.dialPrayers;nextPrayer:root.nextPrayer;language:root.language
        tomorrowLabel:root.tr('tomorrow')
        selectedId:root.selectedInterval?root.selectedInterval.id:''
        accessibleLabel:root.tr('choose')
        onSelected:function(intervalId){root.selectedId=intervalId}
      }
    }
    Row {
      width:parent.width;spacing:Style.space(10)
      Label {width:parent.width*0.3;anchors.verticalCenter:parent.verticalCenter;text:root.time(root.displayAt);font.pixelSize:Style.font.displayLarge;font.bold:true;wrapMode:Text.NoWrap;fontSizeMode:Text.HorizontalFit}
      Column {
        width:parent.width*0.7-parent.spacing-(countdown.visible?countdown.width+parent.spacing:0)
        anchors.verticalCenter:parent.verticalCenter;spacing:Style.space(3)
        Label {width:parent.width;text:root.prayer?root.name(root.prayer.name):root.tr('timetableUnavailable');font.bold:true}
        Label {width:parent.width;text:root.solarPhase?root.name(root.solarPhase.name):'';opacity:0.65;font.pixelSize:Style.font.caption}
      }
      Column {
        id:countdown;objectName:'salah-panel-countdown';visible:!!root.nextPrayer
        width:parent.width*0.3;anchors.verticalCenter:parent.verticalCenter;spacing:Style.space(3)
        Accessible.role:Accessible.StaticText
        Accessible.name:root.nextPrayer?root.tr('nextPrayer')+' '+root.name(root.nextPrayer.name)+' '+root.remaining:''
        Label {width:parent.width;horizontalAlignment:root.language==='ar'?Text.AlignLeft:Text.AlignRight;text:root.nextPrayer?root.name(root.nextPrayer.name):'';font.pixelSize:Style.font.caption;opacity:0.85}
        Label {width:parent.width;horizontalAlignment:root.language==='ar'?Text.AlignLeft:Text.AlignRight;text:root.remaining;font.pixelSize:Style.space(20);font.bold:true;color:root.goldText;wrapMode:Text.NoWrap;fontSizeMode:Text.HorizontalFit}
      }
    }
    Label {width:parent.width;visible:!!root.guidance;text:root.guidance?root.name(root.guidance.name)+' · '+root.tr('estimated'):'';color:'#D99B45';font.pixelSize:Style.font.caption}
    Row {
      width:parent.width
      Label {width:parent.width*0.5;text:root.tr('timeline');font.pixelSize:Style.font.caption;opacity:0.75}
      Button {objectName:'salah-earth-live';text:root.tr('returnNow');visible:root.previewing;focusable:true;onClicked:root.live()}
    }
    PrayerTimeline {
      id:timeline;objectName:'salah-prayer-timeline';width:parent.width
      day:root.day;intervals:root.intervals;prayerEvents:root.dialPrayers;nextPrayer:root.nextPrayer
      at:root.displayAt;language:root.language;accessibleLabel:root.tr('timeline')
      onRequestedAt:function(value){root.preview(Solar.fraction(root.day,value))}
      onPrayerSelected:function(name,value){
        var interval=root.intervals.prayer.filter(function(s){return s.name===name && s.boundaryStart===value})[0]
        if(interval)root.selectedId=interval.id
      }
    }
    Label {width:parent.width;text:root.tr('timelineHint');font.pixelSize:Style.font.caption;opacity:0.6}
    Label {
      width:parent.width;font.pixelSize:Style.font.caption;opacity:0.75
      text:root.position?root.tr('altitude')+' '+root.position.altitude.toFixed(1)+'° · '+root.tr('azimuth')+' '+root.position.azimuth.toFixed(0)+'°\n'+root.tr(root.position.altitude>=0?'above':'below')+' · '+root.tr(root.rising?'rising':'setting'):''
    }
    Label {
      width:parent.width;visible:!!root.nextPrayer;font.pixelSize:Style.font.caption
      text:root.nextPrayer?root.tr('nextPrayer')+' · '+root.name(root.nextPrayer.name)+' · '+root.nextPrayer.time:''
    }
    Label {width:parent.width;visible:root.previewing;text:root.tr('previewHint');font.pixelSize:Style.font.caption;color:'#C5A66F'}
    Row {
      width:parent.width;spacing:Style.space(8)
      Repeater {
        model:root.service.config.guidanceProfile==='diyanet'?['prayerRing','guidanceRing']:['prayerRing']
        Label {
          required property string modelData
          width:(root.width-Style.space(8))/2;font.pixelSize:Style.font.caption
          text:(modelData==='guidanceRing'?'▧ ':'● ')+root.tr(modelData)
          color:modelData==='guidanceRing'?'#D99B45':Color.foreground
        }
      }
    }
    Dropdown {
      width:parent.width;label:root.tr('choose');value:root.selectedInterval?root.selectedInterval.id:''
      options:root.choices.map(function(s){return {value:s.id,label:root.name(s.name)+' · '+root.time(s.start)+(s.estimated?' ≈':'')}})
      onChanged:function(value){root.selectedId=value}
    }
    Rectangle {
      width:parent.width;height:detail.implicitHeight+Style.space(22);radius:Style.space(8)
      color:root.selectedInterval && root.selectedInterval.estimated ? Qt.rgba(0.85,0.61,0.27,0.09):Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.035)
      Column {
        id:detail;x:Style.space(11);y:x;width:parent.width-2*x;spacing:Style.space(7)
        Label {width:parent.width;text:root.selectedInterval?root.name(root.selectedInterval.name):root.tr('details');font.bold:true}
        Label {width:parent.width;text:root.selectedInterval?root.time(root.selectedInterval.start)+'–'+root.time(root.selectedInterval.end)+(root.selectedInterval.estimated?' · '+root.tr('estimated'):''):'';font.pixelSize:Style.font.caption;opacity:0.7}
        Label {width:parent.width;text:root.selectedInterval?root.tr(root.selectedInterval.kind==='prayer' && root.service.config.guidanceProfile!=='diyanet'?'timetable':'explain_'+root.selectedInterval.name):'';font.pixelSize:Style.font.bodySmall}
        Button {text:root.tr('source');visible:!!root.selectedInterval && root.selectedInterval.kind!=='solar' && root.service.config.guidanceProfile==='diyanet';focusable:true;onClicked:Qt.openUrlExternally(EarthText.source)}
      }
    }
    Row {
      width:parent.width;spacing:Style.space(10)
      Repeater {
        model:['sunrise','solarNoon','sunset']
        Column {
          required property string modelData
          width:(root.width-Style.space(20))/3;spacing:Style.space(4)
          Label {width:parent.width;text:root.tr(modelData);font.pixelSize:Style.font.caption;opacity:0.65}
          Label {width:parent.width;text:root.day?root.time(root.day.events[modelData]):'—';font.bold:true}
        }
      }
    }
    Label {width:parent.width;visible:root.intervals.guidanceUnavailable;text:root.tr('guidanceUnavailable');font.pixelSize:Style.font.caption;color:'#D99B45'}
    Label {width:parent.width;visible:root.service.config.guidanceProfile==='diyanet';text:root.tr('guidanceHint');font.pixelSize:Style.font.caption;opacity:0.65}
    Label {width:parent.width;text:root.tr('assumptions');font.pixelSize:Style.font.caption;opacity:0.6}
  }
}
