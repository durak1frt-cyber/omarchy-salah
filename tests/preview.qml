import QtQuick
import Quickshell
import qs.Commons
import "./plugin" as Salah
import "./plugin/SolarModel.js" as Solar

ShellRoot {
  Salah.Service{id:previewService}
  FloatingWindow {
    id:window;visible:true;implicitWidth:480;implicitHeight:940;color:'#182128'
    Rectangle {
      id:frame;width:480;height:940;color:'#182128';clip:true
      scale:Math.min(1,window.width/width,window.height/height);transformOrigin:Item.TopLeft
      Salah.Label{x:20;y:18;text:'Salah';font.bold:true;font.pixelSize:26}
      Salah.Label{x:20;y:54;text:'Istanbul · Demonstration timetable';font.pixelSize:12;opacity:.65}
      Salah.EarthPanel{id:earth;x:20;y:86;width:440;service:previewService}
    }
  }
  Timer {
    id:waitForData;interval:100;running:true;repeat:true
    onTriggered:{
      if(!previewService.ready||previewService.busy||previewService.solarBusy||!earth.day)return
      Color.foreground='#DFE6E8';Color.background='#182128';Color.accent='#DFE6E8';Color.shellValues={}
      earth.preview(Solar.fraction(earth.day,earth.day.events.solarNoon+30*60000))
      waitForData.stop();captureDelay.start()
    }
  }
  Timer {id:captureDelay;interval:300;onTriggered:frame.grabToImage(function(image){
    if(image.saveToFile('PREVIEW_PATH'))console.log('PASS: preview saved')
    else console.error('ERROR: preview could not be saved')
    Qt.quit()
  })}
}
