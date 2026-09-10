// Local display calculations; these never affect prayer times or reminders.
function bearing(location) {
  if(!location)return null
  var lat=location.latitude,lon=location.longitude
  if(typeof lat!=='number'||typeof lon!=='number'||!isFinite(lat)||!isFinite(lon)||Math.abs(lat)>=90||Math.abs(lon)>180)return null
  var rad=Math.PI/180,p=lat*rad,target=21.4225241*rad,d=(39.8261818-lon)*rad
  var east=Math.sin(d)*Math.cos(target)
  var north=Math.cos(p)*Math.sin(target)-Math.sin(p)*Math.cos(target)*Math.cos(d)
  if(Math.sqrt(east*east+north*north)<1e-7)return null
  return (Math.atan2(east,north)/rad+360)%360
}
// Orthographic projection in the same north-up, location-centred camera as Earth.
// A great circle through the camera centre projects to a radial straight line.
function projection(location) {
  if(bearing(location)===null)return null
  var rad=Math.PI/180,p=location.latitude*rad,target=21.4225241*rad,d=(39.8261818-location.longitude)*rad
  var x=Math.cos(target)*Math.sin(d)
  var y=-(Math.cos(p)*Math.sin(target)-Math.sin(p)*Math.cos(target)*Math.cos(d))
  var depth=Math.sin(p)*Math.sin(target)+Math.cos(p)*Math.cos(target)*Math.cos(d)
  var visible=depth>=0
  if(!visible){var length=Math.sqrt(x*x+y*y);x/=length;y/=length}
  return {x:x,y:y,makkahVisible:visible}
}
function coordinates(draft,saved,schedule) {
  if(!draft)return null
  if(draft.provider!=='file' && draft.locationMode==='manual' && typeof draft.latitude==='number' && typeof draft.longitude==='number')
    return {latitude:draft.latitude,longitude:draft.longitude}
  if(!saved||!schedule||!schedule.coordinates||draft.provider!==saved.provider)return null
  if(draft.provider==='file')return draft.scheduleFile===saved.scheduleFile?schedule.coordinates:null
  if(draft.locationMode!==saved.locationMode)return null
  if(draft.locationMode==='auto')return schedule.locationMode==='auto'?schedule.coordinates:null
  // While editing a new city, do not show the previous city's bearing.
  if(draft.city!==saved.city||draft.country!==saved.country||typeof saved.latitude==='number')return null
  return schedule.coordinates
}
if(typeof module!=="undefined")module.exports={bearing:bearing,projection:projection,coordinates:coordinates}
