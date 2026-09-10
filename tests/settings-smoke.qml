import QtQuick
import Quickshell
import "./plugin" as Salah
ShellRoot {
  id:root
  property int step:0
  function check(ok,label){if(!ok){console.error('FAIL: '+label);Qt.quit();throw new Error(label)}}
  function find(item,name){if(item.objectName===name)return item;for(var child of (item.children||item.data||[])){var found=find(child,name);if(found)return found}return null}
  function control(name){var item=find(pane.item,'salah-'+name+'-toggle');check(!!item,'settings control exists: '+name);return item}
  function prayer(name,minutes){var now=Date.now();settingsService.schedule={identity:'bar-fixture',days:[{start:now-86400000,end:now+86400000,events:[{name:name,at:now+minutes*60000,time:'12:00'}]}]}}
  Salah.Service{id:settingsService}
  QtObject {
    id:fakeBar
    property var shell:QtObject{function serviceFor(id){return settingsService}}
    property color foreground:'#d9e2e8'
    property color barForeground:foreground
    property color background:'#182128'
    property color urgent:'#ee7474'
    property string fontFamily:'sans-serif'
    property string position:'top'
    property bool vertical:false
    property int barSize:38
    property bool foregroundAnimationEnabled:false
    property var activePopout:null
    function showTooltip(target,text){} function hideTooltip(target){}
    function registerClickTarget(target){} function unregisterClickTarget(target){}
    function requestPopout(target){} function releasePopout(target){}
    function targetBelongsToWindow(target){return true}
  }
  FloatingWindow {
    visible:true;implicitWidth:420;implicitHeight:720;color:'#182128'
    Salah.Widget{id:barItem;bar:fakeBar;x:12;y:0}
    Flickable {anchors.fill:parent;anchors.topMargin:42;contentHeight:pane.height;clip:true
      Loader{id:pane;active:true;width:parent.width;sourceComponent:Component{Salah.SettingsPane{service:settingsService}}}
    }
  }
  Timer {
    interval:250;running:true;repeat:true
    onTriggered:{
      if(!settingsService.ready||settingsService.busy)return
      if(root.step===0){pane.item.reset();root.check(settingsService.config.locationMode==='manual','starts manual')
      }else if(root.step===1){control('countdown').clicked();pane.active=false
      }else if(root.step===2){pane.active=true
      }else if(root.step===3){root.check(control('countdown').checked && settingsService.config.countdown,'countdown persists when leaving settings');control('auto-location').clicked();pane.active=false
      }else if(root.step===4){pane.active=true
      }else if(root.step===5){
        root.check(control('auto-location').checked && settingsService.config.locationMode==='auto','automatic location persists when leaving settings')
        root.check(settingsService.schedule.locationMode==='auto' && settingsService.schedule.location==='Detected fixture, Test country','detected location supplies the timetable')
        root.check(settingsService.config.latitude===41.0082 && settingsService.config.longitude===28.9784,'manual coordinates preserved')
        control('auto-location').clicked();pane.active=false
      }else if(root.step===6){pane.active=true
      }else if(root.step===7){
        root.check(!control('auto-location').checked && settingsService.config.locationMode==='manual','automatic location can be switched off')
        root.check(settingsService.schedule.locationMode==='manual' && settingsService.schedule.coordinates.latitude===41.0082,'manual timetable restored')
        find(pane.item,'salah-countdown-window').changed('after')
      }else if(root.step===8){
        root.check(settingsService.config.countdownWindow==='after','countdown condition saves immediately');prayer('Fajr',15)
      }else if(root.step===9){
        root.check(!find(barItem,'salah-bar-countdown').visible,'after-only mode hides an approaching countdown')
        find(pane.item,'salah-countdown-window').changed('before')
      }else if(root.step===10){
        var label=find(barItem,'salah-bar-countdown')
        root.check(label.visible && label.text.indexOf('Fajr')>=0 && label.color.toString()==='#e9c46a','Fajr bar countdown is yellow');prayer('Asr',15)
      }else if(root.step===11){
        root.check(find(barItem,'salah-bar-countdown').color.toString()==='#ee7474','Asr approaching countdown is red')
        find(pane.item,'salah-countdown-window').changed('both');prayer('Asr',-5)
      }else if(root.step===12){
        var label=find(barItem,'salah-bar-countdown')
        root.check(label.visible && label.text.indexOf('Asr')>=0 && label.text.indexOf('25m')>=0 && label.color.toString()==='#65c98b','after countdown follows the current green reminder')
        settingsService.acknowledge();root.check(!label.visible,'dismissal hides the countdown')
        console.log('PASS: immediate settings survive closing and reopening');Qt.quit()
      }
      root.step++
    }
  }
}
