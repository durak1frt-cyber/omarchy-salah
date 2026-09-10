import QtQuick

// Resolution-independent artwork; does not depend on a particular icon font.
Item {
  id: root
  property color ink: "white"
  property bool motion: true
  width: 24
  height: width
  function pulse() { if (motion) breath.restart() }
  SequentialAnimation {
    id: breath
    NumberAnimation { target: drawing; property: "opacity"; from: 1; to: 0.65; duration: 450; easing.type: Easing.InOutSine }
    NumberAnimation { target: drawing; property: "opacity"; from: 0.65; to: 1; duration: 650; easing.type: Easing.InOutSine }
  }
  Canvas {
    id: drawing
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.scale(width/24, height/24)
      ctx.strokeStyle = root.ink
      ctx.lineWidth = 1.5
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      // One dome and one minaret, drawn as a quiet outline at bar sizes.
      ctx.beginPath(); ctx.moveTo(4,20); ctx.lineTo(4,14)
      ctx.arc(10,14,6,Math.PI,2*Math.PI)
      ctx.lineTo(16,20); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(4,14); ctx.lineTo(16,14); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(8,20); ctx.lineTo(8,18)
      ctx.quadraticCurveTo(10,14.5,12,18); ctx.lineTo(12,20); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(18.5,20); ctx.lineTo(18.5,7)
      ctx.lineTo(20,4); ctx.lineTo(21.5,7); ctx.lineTo(21.5,20); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(2.5,20); ctx.lineTo(21.5,20); ctx.stroke()
    }
  }
  onInkChanged: drawing.requestPaint()
  onWidthChanged: drawing.requestPaint()
  onHeightChanged: drawing.requestPaint()
  onMotionChanged: if (!motion) { breath.stop(); drawing.opacity = 1 }
}
