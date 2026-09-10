import QtQuick
import QtQuick.Window
import "SolarModel.js" as Solar
import "Qibla.js" as Qibla
import "assets/Land.js" as Land

Item {
  id: root
  property real latitude: 0
  property real longitude: 0
  property var sun: [1,0,0]
  property bool forceFallback: false
  property bool showQibla: false
  property string language: 'en'
  readonly property var qiblaBearing: Qibla.bearing({latitude:latitude,longitude:longitude})
  readonly property var qiblaDestination: Qibla.projection({latitude:latitude,longitude:longitude})
  readonly property var basis: Solar.camera(latitude,longitude)
  readonly property bool fallback: forceFallback || GraphicsInfo.api === GraphicsInfo.Software || shader.status === ShaderEffect.Error
  readonly property int shaderStatus: shader.status
  implicitWidth: 280; implicitHeight: implicitWidth
  Image { id: texture; source: "assets/land-mask.png"; visible: false; smooth: true }
  ShaderEffect {
    id: shader; anchors.fill: parent; visible: !root.fallback
    property var landTexture: texture
    property vector3d sunDirection: Qt.vector3d(root.sun[0],root.sun[1],root.sun[2])
    property vector3d cameraFront: Qt.vector3d(root.basis.front[0],root.basis.front[1],root.basis.front[2])
    property vector3d cameraEast: Qt.vector3d(root.basis.east[0],root.basis.east[1],root.basis.east[2])
    property vector3d cameraNorth: Qt.vector3d(root.basis.north[0],root.basis.north[1],root.basis.north[2])
    fragmentShader: "assets/shaders/earth.frag.qsb"
  }
  Canvas {
    id: canvas; anchors.fill: parent; visible: root.fallback
    onVisibleChanged: if(visible)requestPaint()
    onPaint: {
      if(!visible)return
      var ctx=getContext("2d");ctx.reset();var r=width/2,cx=r,cy=height/2
      var basis=root.basis
      function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]}
      // Orthographic sampling of the bundled mask, without GPU shaders.
      var cell=2
      for(var y=0;y<height;y+=cell)for(var x=0;x<width;x+=cell){
        var px=(x+cell/2-cx)/r,py=(cy-y-cell/2)/r,z2=1-px*px-py*py;if(z2<=0)continue
        var z=Math.sqrt(z2),v=[0,1,2].map(function(k){return px*basis.east[k]+py*basis.north[k]+z*basis.front[k]})
        var lon=Math.atan2(v[1],v[0]),lat=Math.asin(v[2])
        var mx=Math.max(0,Math.min(Land.maskWidth-1,Math.floor((lon/(2*Math.PI)+0.5)*Land.maskWidth)))
        var my=Math.max(0,Math.min(Land.maskHeight-1,Math.floor((0.5-lat/Math.PI)*Land.maskHeight)))
        var land=Land.mask.charAt(my*Land.maskWidth+mx)==='1'
        var light=dot(v,root.sun),amount=Math.max(0,Math.min(1,(light+0.08)/0.18))
        var day=land?[129,152,135]:[23,57,75],night=land?[46,60,70]:[18,26,43],shade=0.7+0.3*z
        ctx.fillStyle=Qt.rgba((night[0]*(1-amount)+day[0]*amount)*shade/255,(night[1]*(1-amount)+day[1]*amount)*shade/255,(night[2]*(1-amount)+day[2]*amount)*shade/255,1)
        // Overlap cell edges to avoid translucent seams at fractional display scales.
        ctx.fillRect(x,y,cell+0.5,cell+0.5)
      }

    }
  }
  QiblaDirection {
    objectName:'salah-qibla-direction';anchors.fill:parent
    bearing:root.qiblaBearing;destination:root.qiblaDestination;language:root.language
    visible:root.showQibla && typeof root.qiblaBearing==='number'
  }
  Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#F2C66D"; border.width: 1.5; border.color: "#F4ECE0" }
  property bool pendingPaint: false
  onSunChanged: if(fallback && visible)pendingPaint=true
  Timer { interval: 100; running: root.fallback && root.visible && root.pendingPaint; onTriggered: { root.pendingPaint=false;canvas.requestPaint() } }
  onBasisChanged: if(fallback && visible)canvas.requestPaint()
  onWidthChanged: if(fallback && visible)canvas.requestPaint()
}
