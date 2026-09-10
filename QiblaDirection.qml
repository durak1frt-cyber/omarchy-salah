import QtQuick
import qs.Commons
import "Strings.js" as Strings

Item {
  id:root
  property var bearing:null
  property var destination:null
  property string language:'en'
  readonly property real tipX:width/2+(destination?destination.x:0)*width/2
  readonly property real tipY:height/2+(destination?destination.y:0)*height/2
  LayoutMirroring.enabled:false
  LayoutMirroring.childrenInherit:false
  Accessible.role:Accessible.Graphic
  Accessible.name:Strings.text('qibla',language)+' · '+(typeof bearing==='number'?bearing.toFixed(1)+'°':'')+' · '+Strings.text('trueNorth',language)
  Accessible.ignored:!visible
  Canvas {
    id:arrow;anchors.fill:parent
    onPaint:{
      var ctx=getContext('2d');ctx.reset();if(!root.destination)return
      var cx=width/2,cy=height/2,vx=root.tipX-cx,vy=root.tipY-cy
      var length=Math.sqrt(vx*vx+vy*vy);if(length<.01)return
      var dx=vx/length,dy=vy/length,gap=Math.min(Style.space(6),length)
      ctx.lineCap='round';ctx.strokeStyle='#B4D5C9';ctx.lineWidth=Style.space(.9)
      for(var start=gap;start<length;start+=Style.space(6)){
        var end=Math.min(length,start+Style.space(2.5))
        ctx.globalAlpha=root.destination.makkahVisible ? 0.6 : 0.6*Math.min(1,(length-start)/Style.space(18))
        ctx.beginPath();ctx.moveTo(cx+dx*start,cy+dy*start);ctx.lineTo(cx+dx*end,cy+dy*end);ctx.stroke()
      }
      // A small endpoint marks Makkah only when it is on the visible hemisphere.
      if(root.destination.makkahVisible && length>Style.space(6)){
        ctx.globalAlpha=.7;ctx.beginPath();ctx.arc(root.tipX,root.tipY,Style.space(1.5),0,2*Math.PI);ctx.stroke()
      }
    }
  }
  Label {
    anchors.horizontalCenter:parent.horizontalCenter;y:Style.space(7)
    text:Strings.text('northShort',root.language);font.pixelSize:Style.space(9);font.bold:true;color:'#DDEBE8'
    style:Text.Outline;styleColor:'#102832'
  }
  onBearingChanged:if(visible)arrow.requestPaint()
  onDestinationChanged:if(visible)arrow.requestPaint()
  onWidthChanged:if(visible)arrow.requestPaint()
  onHeightChanged:if(visible)arrow.requestPaint()
  onVisibleChanged:if(visible)arrow.requestPaint()
}
