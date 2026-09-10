import QtQuick
import qs.Commons
import "SolarModel.js" as Solar
import "DialLayout.js" as Layout
import "Strings.js" as Strings

Item {
  id: root
  property var day: null
  property var intervals: ({prayer:[],solar:[],guidance:[]})
  property var prayerEvents: []
  property var nextPrayer: null
  property string language: "en"
  property string tomorrowLabel: "Tomorrow"
  property double at: 0
  property color foreground: "#DFE6E8"
  property string selectedId: ""
  property string accessibleLabel: "Prayer intervals"
  readonly property real radius: Math.max(70,Math.min(width,height)/2-Style.space(52))
  readonly property real labelWidth: Style.space(52)
  readonly property real labelHeight: Style.space(28)
  readonly property var ticks: Solar.clockTicks(day)
  readonly property var labels: Layout.labels(day,prayerEvents,width,height,radius,labelWidth,labelHeight,Style.space(5))
  readonly property real angle: day?Solar.fraction(day,at)*2*Math.PI-Math.PI/2:0
  readonly property real markerX: width/2+Math.cos(angle)*radius
  readonly property real markerY: height/2+Math.sin(angle)*radius
  readonly property color goldText: foreground.r+foreground.g+foreground.b>1.5?"#F2C66D":"#895A10"
  signal selected(string intervalId)
  activeFocusOnTab: true
  Accessible.role: Accessible.List
  Accessible.name: accessibleLabel
  Keys.onLeftPressed: step(-1)
  Keys.onRightPressed: step(1)
  function step(delta){
    var list=intervals.prayer.concat(intervals.guidance);if(!list.length)return
    var index=list.map(function(s){return s.id}).indexOf(selectedId)
    selected(list[(index+delta+list.length)%list.length].id)
  }
  function choosePrayer(event){
    var interval=intervals.prayer.filter(function(s){return s.name===event.name && s.boundaryStart===event.at})[0]
    if(interval)selected(interval.id)
  }
  function redraw(){if(visible)drawing.requestPaint()}
  Canvas {
    id:drawing;anchors.fill:parent
    onPaint:{
      var ctx=getContext('2d');ctx.reset();if(!root.day)return
      var cx=width/2,cy=height/2,twopi=2*Math.PI,r=root.radius
      function angle(t){return Solar.fraction(root.day,t)*twopi-Math.PI/2}
      function ring(list,radius,thickness){
        ctx.lineWidth=thickness;ctx.lineCap='butt'
        list.forEach(function(s){
          var start=angle(s.start),end=angle(s.end),gap=Math.min(0.007,(end-start)/8)
          ctx.strokeStyle=Solar.colour(s);ctx.globalAlpha=s.id===root.selectedId?1:0.8
          ctx.beginPath();ctx.arc(cx,cy,radius,start+gap,end-gap);ctx.stroke()
          if(s.kind==='guidance'){
            ctx.strokeStyle=root.foreground;ctx.globalAlpha=0.65;ctx.lineWidth=1
            for(var a=start+0.006;a<end;a+=0.025){ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*(radius-thickness/2),cy+Math.sin(a)*(radius-thickness/2));ctx.lineTo(cx+Math.cos(a+0.012)*(radius+thickness/2),cy+Math.sin(a+0.012)*(radius+thickness/2));ctx.stroke()}
            ctx.lineWidth=thickness
          }
          if(root.activeFocus && s.id===root.selectedId){ctx.lineWidth=1;ctx.strokeStyle=root.foreground;ctx.beginPath();ctx.arc(cx,cy,radius+thickness/2+2,start,end);ctx.stroke();ctx.lineWidth=thickness}
        })
      }
      ring(root.intervals.prayer,r,Style.space(5));ring(root.intervals.guidance,r-Style.space(9),Style.space(3))
      root.ticks.forEach(function(t){
        var a=angle(t.at),length=Style.space(t.major?5:2.5),outer=r+Style.space(4)
        ctx.lineWidth=t.major?1:0.8;ctx.strokeStyle=root.foreground;ctx.globalAlpha=t.major?0.42:0.24
        ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*outer,cy+Math.sin(a)*outer);ctx.lineTo(cx+Math.cos(a)*(outer+length),cy+Math.sin(a)*(outer+length));ctx.stroke()
        if(t.major && t.hour%3===0){
          ctx.fillStyle=root.foreground;ctx.globalAlpha=0.5;ctx.font=Style.space(8)+'px sans-serif';ctx.textAlign='center';ctx.textBaseline='middle'
          ctx.fillText(String(t.hour).padStart(2,'0'),cx+Math.cos(a)*(r-Style.space(16)),cy+Math.sin(a)*(r-Style.space(16)))
        }
      })
      root.labels.forEach(function(p){
        var px=cx+Math.cos(p.angle)*(r+Style.space(4)),py=cy+Math.sin(p.angle)*(r+Style.space(4))
        var tx=Math.max(p.x,Math.min(p.x+root.labelWidth,px)),ty=Math.max(p.y,Math.min(p.y+root.labelHeight,py))
        ctx.globalAlpha=0.23;ctx.strokeStyle=root.foreground;ctx.lineWidth=0.8
        ctx.beginPath();ctx.moveTo(px,py);ctx.lineTo(tx,ty);ctx.stroke()
        ctx.globalAlpha=0.65;ctx.fillStyle=root.foreground;ctx.beginPath();ctx.arc(cx+Math.cos(p.angle)*r,cy+Math.sin(p.angle)*r,Style.space(1.4),0,twopi);ctx.fill()
      })
    }
  }
  MouseArea {anchors.fill:parent;onClicked:function(mouse){
    if(!root.day)return
    var x=mouse.x-width/2,y=mouse.y-height/2,r=Math.sqrt(x*x+y*y)
    var list=Math.abs(r-root.radius)<Style.space(7)?root.intervals.prayer:Math.abs(r-(root.radius-Style.space(9)))<Style.space(4)?root.intervals.guidance:[]
    var f=((Math.atan2(y,x)+Math.PI/2+2*Math.PI)%(2*Math.PI))/(2*Math.PI)
    var interval=Solar.active(list,Solar.atFraction(root.day,f))
    if(interval){root.forceActiveFocus();root.selected(interval.id)}
  }}
  Repeater {
    model:root.labels
    Item {
      id:prayerLabel
      required property var modelData
      readonly property bool upcoming: !!root.nextPrayer && root.nextPrayer.name===modelData.event.name
      readonly property var displayEvent: upcoming?root.nextPrayer:modelData.event
      readonly property bool tomorrow: !!root.day && displayEvent.at>=root.day.end
      readonly property bool timeVisible: upcoming || labelMouse.containsMouse || activeFocus
      objectName:'salah-prayer-label-'+modelData.event.name
      x:modelData.x;y:modelData.y;width:root.labelWidth;height:root.labelHeight
      activeFocusOnTab:true
      Keys.onReturnPressed:root.choosePrayer(modelData.event)
      Keys.onSpacePressed:root.choosePrayer(modelData.event)
      Accessible.role:Accessible.Button
      Accessible.name:Strings.prayer(modelData.event.name,root.language)+' '+displayEvent.time+(tomorrow?' '+root.tomorrowLabel:'')
      Accessible.onPressAction:{forceActiveFocus();root.choosePrayer(modelData.event)}
      Column {
        anchors.centerIn:parent;width:parent.width;spacing:Style.space(1)
        Label {width:parent.width;horizontalAlignment:Text.AlignHCenter;text:Strings.prayer(modelData.event.name,root.language);font.pixelSize:Style.space(9);opacity:prayerLabel.upcoming?1:0.75;color:prayerLabel.upcoming?root.goldText:root.foreground}
        Label {
          width:parent.width;horizontalAlignment:Text.AlignHCenter
          text:prayerLabel.displayEvent.time+(prayerLabel.tomorrow?' +1':'')
          font.pixelSize:Style.space(10);font.bold:true
          opacity:prayerLabel.timeVisible?1:0;Accessible.ignored:!prayerLabel.timeVisible
        }
      }
      MouseArea {id:labelMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.choosePrayer(parent.modelData.event)}
    }
  }
  Item {
    objectName:'salah-sun-marker';visible:!!root.day
    x:root.markerX-width/2;y:root.markerY-height/2;width:Style.space(22);height:width
    Accessible.role:Accessible.StaticText
    Accessible.name:root.day?Solar.clock(root.day,root.at):''
    Rectangle {anchors.centerIn:parent;width:parent.width;height:width;radius:width/2;color:'#F2C66D';opacity:0.12}
    Canvas {
      anchors.fill:parent
      onPaint:{
        var ctx=getContext('2d');ctx.reset();var r=width/2;ctx.strokeStyle='#E4AD48';ctx.lineWidth=1.2;ctx.lineCap='round'
        for(var i=0;i<8;i++){var a=i*Math.PI/4;ctx.beginPath();ctx.moveTo(r+Math.cos(a)*r*0.65,r+Math.sin(a)*r*0.65);ctx.lineTo(r+Math.cos(a)*r*0.85,r+Math.sin(a)*r*0.85);ctx.stroke()}
        ctx.fillStyle='#F2C66D';ctx.beginPath();ctx.arc(r,r,r*0.43,0,2*Math.PI);ctx.fill();ctx.strokeStyle='#FFE5A4';ctx.lineWidth=1;ctx.stroke()
      }
    }
  }
  onIntervalsChanged:redraw()
  onLabelsChanged:redraw()
  onTicksChanged:redraw()
  onSelectedIdChanged:redraw()
  onForegroundChanged:redraw()
  onWidthChanged:redraw()
  onActiveFocusChanged:redraw()
  onVisibleChanged:if(visible)redraw()
}
