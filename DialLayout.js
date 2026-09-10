// Place prayer labels outside the clock without changing their timed anchors.
function labels(day, events, width, height, radius, boxWidth, boxHeight, gap) {
  if (!day) return []
  var result=events.map(function(event) {
    var angle=(event.at-day.start)/(day.end-day.start)*2*Math.PI-Math.PI/2
    var c=Math.cos(angle),s=Math.sin(angle),px=width/2+c*(radius+6),py=height/2+s*(radius+6)
    var side=c>0.4?'right':c< -0.4?'left':'middle'
    var x=side==='right'?px+gap:side==='left'?px-gap-boxWidth:px-boxWidth/2
    var y=side==='middle'?(s<0?py-gap-boxHeight:py+gap):py-boxHeight/2
    return {event:event,angle:angle,px:px,py:py,side:side,
      x:Math.max(0,Math.min(width-boxWidth,x)),y:Math.max(0,Math.min(height-boxHeight,y))}
  })
  ;['left','right','middle'].forEach(function(side) {
    var group=result.filter(function(p){return p.side===side}).sort(function(a,b){return a.y-b.y})
    for(var i=1;i<group.length;i++)group[i].y=Math.max(group[i].y,group[i-1].y+boxHeight+gap)
    if(group.length && group[group.length-1].y+boxHeight>height){
      group[group.length-1].y=height-boxHeight
      for(var j=group.length-2;j>=0;j--)group[j].y=Math.min(group[j].y,group[j+1].y-boxHeight-gap)
    }
  })
  return result
}
function timeline(day, events, width, boxWidth, gap) {
  if(!day)return []
  var ends=[]
  return events.slice().sort(function(a,b){return a.at-b.at}).map(function(event){
    var point=(event.at-day.start)/(day.end-day.start)*width
    var x=Math.max(0,Math.min(width-boxWidth,point-boxWidth/2)),row=0
    while(row<ends.length && x<ends[row]+gap)row++
    ends[row]=x+boxWidth
    return {event:event,point:point,x:x,row:row}
  })
}
if(typeof module!=="undefined")module.exports={labels:labels,timeline:timeline}
