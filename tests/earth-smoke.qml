import QtQuick
import Quickshell
import QtTest
import qs.Commons
import "./plugin" as Salah
import "./plugin/SolarModel.js" as Solar
ShellRoot {
  id:harness
  property int step:0
  property string baseline:""
  property int panelWidth:420
  property bool doneCapture:true
  property bool interacting:false
  property bool failed:false
  property string captureName:''
  property var qiblaSchedule:null
  property var qiblaSolar:null
  function toggleQibla() {
    qiblaSettings.active=true
    find(qiblaSettings.item,'salah-qibla-toggle').clicked()
    qiblaSettings.active=false
  }
  function check(ok,label){if(!ok){failed=true;console.error('FAIL: '+label);Qt.quit();throw new Error(label)}}
  function find(item,name){if(item.objectName===name)return item;var items=item.data||item.children||[];for(var i=0;i<items.length;i++){var r=find(items[i],name);if(r)return r}if(item.contentItem)return find(item.contentItem,name);return null}
  function snapshot(name){doneCapture=false;captureName=name;captureDelay.restart()}
  // Let layout settle after a saved setting briefly reloads local solar data.
  Timer {id:captureDelay;interval:60;onTriggered:frame.grabToImage(function(r){r.saveToFile('OUTPUT_DIR/'+harness.captureName+'.png');harness.doneCapture=true})}
  function interactions(earth) {
    interacting=true
    try {
    var dial=find(earth,'salah-interval-dial'),fajr=find(dial,'salah-prayer-label-Fajr'),asr=find(dial,'salah-prayer-label-Asr')
    viewport.contentY=Math.max(0,fajr.mapToItem(viewport,0,0).y+viewport.contentY-40);pointer.wait(30)
    check(!fajr.timeVisible && asr.timeVisible,'only upcoming prayer time visible by default')
    pointer.mouseMove(fajr);pointer.wait(20)
    check(fajr.timeVisible,'hover reveals another prayer time')
    pointer.mouseMove(viewport,2,2);pointer.wait(20)
    check(!fajr.timeVisible,'leaving hides the prayer time')
    fajr.forceActiveFocus();check(fajr.timeVisible,'keyboard focus reveals prayer time')
    viewport.forceActiveFocus();check(!fajr.timeVisible,'leaving keyboard focus hides time')
    var timeline=find(earth,'salah-prayer-timeline'),slider=find(timeline,'salah-earth-slider')
    viewport.contentY=Math.max(0,timeline.mapToItem(viewport,0,0).y+viewport.contentY-80);pointer.wait(20)
    var x=timeline.inset+timeline.trackWidth*.25,y=timeline.horizonY
    pointer.mouseMove(timeline,x,y);pointer.wait(100)
    check(timeline.inspecting && timeline.hoverText.length>0,'timeline hover shows time and interval')
    pointer.mouseClick(timeline,x,y);pointer.wait(20)
    check(earth.previewing && Math.abs(Solar.fraction(earth.day,earth.displayAt)-.25)<.002,'timeline click previews matching time')
    pointer.mousePress(timeline,x,y)
    pointer.mouseMove(timeline,timeline.inset+timeline.trackWidth*.75,y,20,Qt.LeftButton)
    pointer.mouseRelease(timeline,timeline.inset+timeline.trackWidth*.75,y);pointer.wait(20)
    check(Math.abs(Solar.fraction(earth.day,earth.displayAt)-.75)<.002,'drag moves the globe preview')
    var dhuhr=earth.dialPrayers.filter(function(p){return p.name==='Dhuhr'})[0]
    pointer.mouseClick(find(timeline,'salah-timeline-prayer-Dhuhr'));pointer.wait(20)
    check(Math.abs(earth.displayAt-dhuhr.at)<1 && earth.selectedInterval.name==='Dhuhr','prayer click opens its exact time and details')
    slider.forceActiveFocus();pointer.keyClick(Qt.Key_Right);pointer.wait(20)
    check(Math.abs(earth.displayAt-dhuhr.at-60000)<1,'keyboard advances timeline by one minute')
    pointer.mouseClick(find(earth,'salah-earth-live'));pointer.wait(20)
    check(!earth.previewing,'return to now exits interactive preview')
    check(JSON.stringify(earthService.memory)===baseline,'timeline interactions leave reminder state unchanged')
    viewport.contentY=0;viewport.forceActiveFocus();pointer.mouseMove(frame,2,2)
    earth.preview(Solar.fraction(earth.day,earth.day.events.solarNoon+30*60000))
    } finally {interacting=false}
  }
  Salah.Service{id:earthService}
  Loader {id:qiblaSettings;active:false;sourceComponent:Component{Salah.SettingsPane{service:earthService;width:360}}}
  FloatingWindow {
    visible:true;implicitWidth:460;implicitHeight:850;color:Color.background
    TestCase {id:pointer;name:'Earth interactions';when:false}
    Flickable {
      id:viewport
      anchors.fill:parent;contentWidth:width;contentHeight:frame.height*frame.scale;clip:true
      Rectangle {
        id:frame;width:harness.panelWidth+24;height:loader.item?loader.item.implicitHeight+64:100;color:Color.background
        // The compositor may tile this test window narrower than its requested size.
        scale:Math.min(1,viewport.width/width);transformOrigin:Item.TopLeft
        Salah.Label {x:12;y:12;text:'Salah';font.bold:true;font.pixelSize:24}
        Loader {id:loader;x:12;y:52;width:harness.panelWidth;active:true;sourceComponent:Component{Salah.EarthPanel {service:earthService}}}
      }
    }
  }
  Loader {id:second;active:false;sourceComponent:Component{Salah.EarthPanel{service:earthService;width:360}}}
  Timer {
    interval:350;running:!harness.failed;repeat:true
    onTriggered:{
      if(!earthService.ready||earthService.busy||earthService.solarBusy||!harness.doneCapture||harness.interacting)return
      var earth=loader.item
      if(step<17 && (!earth||!earth.day))return
      if(step===0){
        Color.foreground='#DFE6E8';Color.background='#182128';Color.accent='#DFE6E8';Color.shellValues={}
        check(earth.intervals.guidance.length===3,'three guidance bands')
        check(earthService.earthVisible,'Earth registered visible consumer')
        check(!find(earth,'salah-qibla-direction').visible,'qibla overlay defaults off')
        harness.baseline=JSON.stringify(earthService.memory)
        earth.preview(Solar.fraction(earth.day,earth.day.events.solarNoon+30*60000))
      }else if(step===1){
        var globe=find(earth,'salah-earth-globe');check(!!globe,'globe loads')
        check(globe.shaderStatus===ShaderEffect.Compiled || globe.fallback,'GPU shader compiles or fallback selected')
        check(earth.previewing && earth.displayAt!==earthService.now,'preview clock separate from live clock')
        check(JSON.stringify(earthService.memory)===baseline,'preview leaves reminder memory unchanged')
        var dial=find(earth,'salah-interval-dial')
        check(dial.prayerEvents.length===5,'five dated prayer labels')
        check(dial.ticks.length===48,'hour and half-hour marks')
        check(earth.nextPrayer.name==='Asr','countdown targets the next prayer')
        check(earth.remaining===Solar.countdown(earth.nextPrayer.at,earth.displayAt),'countdown follows preview time')
        check(find(dial,'salah-sun-marker').visible,'sun replaces the hand')
        check(find(dial,'salah-prayer-label-Fajr').visible,'exact prayer time label visible')
        interactions(earth);snapshot('daylight')
      }else if(step===2){earth.preview(Solar.fraction(earth.day,earth.day.events.sunrise));harness.qiblaSchedule=earthService.schedule;harness.qiblaSolar=earthService.solarData;toggleQibla()
      }else if(step===3){
        check(earth.guidance && earth.guidance.name==='sunriseGuidance','sunrise guidance selected')
        var direction=find(earth,'salah-qibla-direction')
        check(direction.visible && Math.abs(direction.bearing-151.6)<.1,'saved qibla toggle shows the local bearing')
        check(earthService.schedule===harness.qiblaSchedule && earthService.solarData===harness.qiblaSolar,'Qibla toggle keeps timetable and solar data loaded')
        check(direction.tipX>direction.width/2 && direction.tipY>direction.height/2,'north-up globe points southeast toward Makkah')
        snapshot('sunrise')
      }else if(step===4){earth.preview(Solar.fraction(earth.day,earth.day.events.sunset-20*60000))
      }else if(step===5){check(earth.guidance && earth.guidance.name==='sunsetGuidance','sunset guidance selected');snapshot('sunset')
      }else if(step===6){earth.preview(0.95)
      }else if(step===7){check(earth.nextPrayer.name==='Fajr' && earth.nextPrayer.at>=earth.day.end,'night countdown uses tomorrow’s dated Fajr');var fajr=find(earth,'salah-prayer-label-Fajr');check(fajr.timeVisible && fajr.tomorrow && fajr.displayEvent.at===earth.nextPrayer.at,'upcoming Fajr label shows tomorrow’s exact time');snapshot('night')
      }else if(step===8){earth.forceFallback=true;earth.preview(0.5)
      }else if(step===9){check(find(earth,'salah-earth-globe').fallback,'software fallback selected');snapshot('fallback')
      }else if(step===10){earth.forceFallback=false;earthService.config=Object.assign({},earthService.config,{language:'tr',motion:false});harness.panelWidth=360
      }else if(step===11){snapshot('turkish-360')
      }else if(step===12){earthService.config=Object.assign({},earthService.config,{language:'ar'});Color.foreground='#23323C';Color.background='#F1F3EE';Color.accent='#23323C'
      }else if(step===13){snapshot('arabic-light')
      }else if(step===14){var slider=find(earth,'salah-earth-slider');check(slider.activeFocusOnTab,'slider keyboard access');find(earth,'salah-earth-live').clicked();check(!earth.previewing,'return to now');check(JSON.stringify(earthService.memory)===baseline,'all previews leave memory unchanged');second.active=true;toggleQibla()
      }else if(step===15){check(!find(earth,'salah-qibla-direction').visible,'saved toggle hides qibla again');check(earthService.earthUsers.length===2,'two panel consumers');second.active=false
      }else if(step===16){check(earthService.earthUsers.length===1,'closing one monitor keeps the other');loader.active=false
      }else if(step===17){check(!earthService.earthVisible,'closing all panels stops render consumers');loader.active=true
      }else if(step===18){check(!loader.item.previewing,'reopen resets preview');earthService.receiveSchedule({error:'Synthetic offline failure',code:'provider_unavailable'});check(!!earth.day && !!earth.position,'solar view remains available during provider outage');earthService.config=Object.assign({},earthService.config,{guidanceProfile:'off'})
      }else if(step===19){check(earth.intervals.guidance.length===0,'guidance can be disabled');earthService.schedule=Object.assign({},earthService.schedule,{coordinates:null})
      }else if(step===20){check(!earth.day && !earthService.solarLocationKey,'missing import coordinates disables only solar view');check(!!earthService.today,'timetable remains usable');console.log('PASS: earth, shader, guidance, preview isolation, keyboard, RTL, fallback, consumers, offline, missing coordinates');Qt.quit()}
      step++
    }
  }
}
