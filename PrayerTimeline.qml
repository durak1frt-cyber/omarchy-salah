import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import "SolarModel.js" as Solar
import "DialLayout.js" as Layout
import "Strings.js" as Strings
import "EarthStrings.js" as EarthText

Item {
  id: root
  property var day: null
  property var intervals: ({prayer:[],solar:[],guidance:[]})
  property var prayerEvents: []
  property var nextPrayer: null
  property double at: 0
  property string language: 'en'
  property string accessibleLabel: 'Prayer timeline'
  readonly property real inset: Style.space(6)
  readonly property real trackWidth: Math.max(1,width-2*inset)
  readonly property real chartTop: Style.space(22)
  readonly property real horizonY: Style.space(40)
  readonly property real amplitude: Style.space(23)
  readonly property real trackY: Style.space(72)
  readonly property real labelWidth: Style.space(54)
  readonly property real rowHeight: Style.space(27)
  readonly property var labels: Layout.timeline(day,prayerEvents,trackWidth,labelWidth,Style.space(4))
  readonly property int rows: labels.reduce(function(count,p){return Math.max(count,p.row+1)},0)
  readonly property var ticks: Solar.clockTicks(day)
  readonly property var position: Solar.position(day,at)
  readonly property real currentX: day?inset+Solar.fraction(day,at)*trackWidth:inset
  readonly property real currentY: position?horizonY-position.altitude/90*amplitude:horizonY
  readonly property bool inspecting: hover.hovered && hover.point.position.y>=chartTop && hover.point.position.y<=trackY+Style.space(12)
  readonly property real hoverAt: day?Solar.atFraction(day,(hover.point.position.x-inset)/trackWidth):0
  readonly property var hoverPrayer: day?prayerEvents.filter(function(p){return Math.abs(Solar.fraction(root.day,p.at)*root.trackWidth+root.inset-hover.point.position.x)<Style.space(8)})[0]||null:null
  readonly property var hoverInterval: Solar.active(intervals.prayer,hoverAt)
  readonly property string hoverText: {
    if(hoverPrayer)return Strings.prayer(hoverPrayer.name,language)+' · '+hoverPrayer.time
    if(!day)return ''
    var name=hoverInterval?(hoverInterval.name==='morning'?EarthText.text('morning',language):Strings.prayer(hoverInterval.name,language)):''
    return Solar.clock(day,hoverAt)+(name?' · '+name:'')
  }
  readonly property color gold: Color.foreground.r+Color.foreground.g+Color.foreground.b>1.5?'#F2C66D':'#895A10'
  signal requestedAt(double value)
  signal prayerSelected(string name, double value)
  implicitHeight: trackY+Style.space(25)+rows*rowHeight
  LayoutMirroring.enabled:false
  LayoutMirroring.childrenInherit:false
  function jump(event){requestedAt(event.at);prayerSelected(event.name,event.at)}
  function redraw(){if(visible)chart.requestPaint()}
  Canvas {
    id:chart;anchors.fill:parent
    onPaint:{
      var ctx=getContext('2d');ctx.reset();if(!root.day)return
      function x(at){return root.inset+Solar.fraction(root.day,at)*root.trackWidth}
      root.intervals.solar.forEach(function(s){ctx.fillStyle=Solar.colour(s);ctx.globalAlpha=0.07;ctx.fillRect(x(s.start),root.chartTop,x(s.end)-x(s.start),root.trackY-root.chartTop-Style.space(8))})
      ctx.strokeStyle=Color.foreground;ctx.lineWidth=1;ctx.globalAlpha=0.2
      ctx.beginPath();ctx.moveTo(root.inset,root.horizonY);ctx.lineTo(width-root.inset,root.horizonY);ctx.stroke()
      ctx.globalAlpha=0.65;ctx.lineWidth=1.3;ctx.beginPath()
      var samples=root.day.samples
      for(var i=0;i<samples.length;i+=3){var px=x(samples[i][0]),py=root.horizonY-samples[i][4]/90*root.amplitude;if(!i)ctx.moveTo(px,py);else ctx.lineTo(px,py)}
      var last=samples[samples.length-1];ctx.lineTo(x(last[0]),root.horizonY-last[4]/90*root.amplitude);ctx.stroke()
      ctx.globalAlpha=0.15;ctx.fillStyle=Color.foreground;ctx.fillRect(root.inset,root.trackY,root.trackWidth,Style.space(4))
      root.intervals.prayer.forEach(function(s){ctx.fillStyle=Solar.colour(s);ctx.globalAlpha=0.9;ctx.fillRect(x(s.start),root.trackY,Math.max(1,x(s.end)-x(s.start)-1),Style.space(4))})
      root.intervals.guidance.forEach(function(s){
        ctx.fillStyle='#D99B45';ctx.globalAlpha=0.65;ctx.fillRect(x(s.start),root.trackY+Style.space(6),x(s.end)-x(s.start),Style.space(3))
        ctx.strokeStyle=Color.background;ctx.lineWidth=1;ctx.globalAlpha=0.6
        for(var px=x(s.start);px<x(s.end)-2;px+=4){ctx.beginPath();ctx.moveTo(px,root.trackY+Style.space(6));ctx.lineTo(px+2,root.trackY+Style.space(9));ctx.stroke()}
      })
      root.ticks.filter(function(t){return t.major&&t.hour%6===0}).forEach(function(t){
        ctx.strokeStyle=Color.foreground;ctx.globalAlpha=0.3;ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x(t.at),root.trackY-Style.space(4));ctx.lineTo(x(t.at),root.trackY);ctx.stroke()
        ctx.fillStyle=Color.foreground;ctx.globalAlpha=0.5;ctx.font=Style.space(8)+'px sans-serif';ctx.textBaseline='top';ctx.textAlign=t.at===root.day.start?'left':'center';ctx.fillText(String(t.hour).padStart(2,'0'),x(t.at),root.trackY+Style.space(11))
      })
      ctx.textAlign='right';ctx.fillText('24',width-root.inset,root.trackY+Style.space(11))
      root.labels.forEach(function(p){
        ctx.globalAlpha=0.65;ctx.fillStyle=Color.foreground;ctx.beginPath();ctx.arc(root.inset+p.point,root.trackY+Style.space(2),Style.space(2),0,Math.PI*2);ctx.fill()
        ctx.globalAlpha=0.15;ctx.strokeStyle=Color.foreground;ctx.lineWidth=0.8;ctx.beginPath();ctx.moveTo(root.inset+p.point,root.trackY+Style.space(20));ctx.lineTo(root.inset+p.x+root.labelWidth/2,root.trackY+Style.space(23)+p.row*root.rowHeight);ctx.stroke()
      })
    }
  }
  Rectangle {
    visible:!!root.day;x:root.currentX;width:1;y:root.chartTop;height:root.trackY-root.chartTop+Style.space(5)
    color:root.gold;opacity:0.3
  }
  Rectangle {
    visible:!!root.position;x:root.currentX-width/2;y:root.currentY-height/2
    width:Style.space(7);height:width;radius:width/2;color:'#F2C66D';border.width:1;border.color:'#FFE5A4'
  }
  Rectangle {
    visible:!!root.day;x:root.currentX-width/2;y:root.trackY+Style.space(2)-height/2
    width:Style.space(8);height:width;radius:width/2;color:'#F2C66D';border.width:1;border.color:Color.background
  }
  QQC.Slider {
    id:scrubber;objectName:'salah-earth-slider';anchors.top:parent.top;width:parent.width;height:root.trackY+Style.space(12)
    leftPadding:root.inset;rightPadding:root.inset;topPadding:0;bottomPadding:0
    from:0;to:1;enabled:!!root.day;activeFocusOnTab:true
    stepSize:root.day?60000/(root.day.end-root.day.start):0.001
    value:root.day?Solar.fraction(root.day,root.at):0
    background:Item {}
    handle:Item {implicitWidth:0;implicitHeight:0}
    Accessible.name:root.accessibleLabel
    onMoved:root.requestedAt(Solar.atFraction(root.day,value))
  }
  Rectangle {
    anchors.left:parent.left;anchors.right:parent.right;y:root.chartTop-Style.space(3);height:root.trackY-root.chartTop+Style.space(17)
    color:'transparent';radius:Style.space(3);border.width:scrubber.activeFocus?1:0;border.color:root.gold
  }
  HoverHandler {id:hover}
  Rectangle {
    visible:root.inspecting
    width:Math.min(root.width,hoverLabel.implicitWidth+Style.space(12));height:Style.space(20);radius:Style.space(4)
    x:Math.max(0,Math.min(root.width-width,hover.point.position.x-width/2));y:0;color:Color.background
    Label {id:hoverLabel;anchors.centerIn:parent;text:root.hoverText;font.pixelSize:Style.space(9);color:root.gold}
  }
  Repeater {
    model:root.labels
    Rectangle {
      id:prayerLabel
      required property var modelData
      objectName:'salah-timeline-prayer-'+modelData.event.name
      readonly property bool upcoming: !!root.nextPrayer && root.nextPrayer.at===modelData.event.at
      x:root.inset+modelData.x;y:root.trackY+Style.space(23)+modelData.row*root.rowHeight
      width:root.labelWidth;height:root.rowHeight-Style.space(2);radius:Style.space(3);color:Color.background
      activeFocusOnTab:true;border.width:activeFocus?1:0;border.color:root.gold
      Accessible.role:Accessible.Button
      Accessible.name:Strings.prayer(modelData.event.name,root.language)+' '+modelData.event.time
      Accessible.onPressAction:root.jump(modelData.event)
      Keys.onReturnPressed:root.jump(modelData.event)
      Keys.onSpacePressed:root.jump(modelData.event)
      Column {
        anchors.centerIn:parent;width:parent.width;spacing:Style.space(1)
        Label {width:parent.width;horizontalAlignment:Text.AlignHCenter;text:Strings.prayer(modelData.event.name,root.language);font.pixelSize:Style.space(9);color:prayerLabel.upcoming?root.gold:Color.foreground;opacity:prayerLabel.upcoming?1:0.7}
        Label {width:parent.width;horizontalAlignment:Text.AlignHCenter;text:modelData.event.time;font.pixelSize:Style.space(10);font.bold:prayerLabel.upcoming}
      }
      MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.jump(parent.modelData.event)}
    }
  }
  onDayChanged:redraw()
  onIntervalsChanged:redraw()
  onLabelsChanged:redraw()
  onTicksChanged:redraw()
  onWidthChanged:redraw()
  onVisibleChanged:if(visible)redraw()
  Connections {target:Color;function onForegroundChanged(){root.redraw()}function onBackgroundChanged(){root.redraw()}}
}
