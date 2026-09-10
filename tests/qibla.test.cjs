const {test}=require('node:test');const assert=require('node:assert/strict');const Q=require('../Qibla.js');
test('Qibla guide ends at the actual projected Makkah position across locations',()=>{
  const S=require('../SolarModel.js'),r=Math.PI/180;
  const target=[Math.cos(21.4225241*r)*Math.cos(39.8261818*r),Math.cos(21.4225241*r)*Math.sin(39.8261818*r),Math.sin(21.4225241*r)];
  const dot=(a,b)=>a.reduce((sum,v,i)=>sum+v*b[i],0);
  for(const [latitude,longitude] of [[41.0082,28.9784],[51.5,-.12],[-6.2,106.8],[-33.87,151.21],[40.7,-74],[21.5,39.9],[0,179]]){
    const camera=S.camera(latitude,longitude),point=Q.projection({latitude,longitude});
    const depth=dot(camera.front,target);
    assert.equal(point.makkahVisible,depth>=0);
    if(depth>=0){assert.ok(Math.abs(point.x-dot(camera.east,target))<1e-12);assert.ok(Math.abs(point.y+dot(camera.north,target))<1e-12)}
    else assert.ok(Math.abs(Math.hypot(point.x,point.y)-1)<1e-12,'far-side routes clip at the horizon');
    const angle=(Math.atan2(point.x,-point.y)/r+360)%360;
    assert.ok(Math.abs(angle-Q.bearing({latitude,longitude}))<1e-10);
  }
  assert.ok(Math.hypot(...['x','y'].map(k=>Q.projection({latitude:21.5,longitude:39.9})[k]))<.01,'near Makkah route is short');
  assert.equal(Q.projection({latitude:21.4225241,longitude:39.8261818}),null);
});
test('qibla bearings work across hemispheres and preserve true-north convention',()=>{
  for(const [latitude,longitude,expected] of [[41.0082,28.9784,151.6],[19.08,72.88,280.1],[-6.2,106.8,295.2],[30.04,31.24,136.1]])
    assert.ok(Math.abs(Q.bearing({latitude,longitude})-expected)<.1);
  assert.equal(Q.bearing({latitude:10,longitude:39.8261818}),0);
  assert.equal(Q.bearing({latitude:40,longitude:39.8261818}),180);
});
test('invalid, coincident, antipodal and polar locations have no invented direction',()=>{
  for(const location of [null,{}, {latitude:'37',longitude:42},{latitude:NaN,longitude:0},{latitude:0,longitude:Infinity},{latitude:91,longitude:0},{latitude:90,longitude:10},{latitude:-90,longitude:10},{latitude:0,longitude:181},{latitude:21.4225241,longitude:39.8261818},{latitude:-21.4225241,longitude:-140.1738182}])assert.equal(Q.bearing(location),null);
});
test('settings use draft coordinates and never borrow a previous city or provider location',()=>{
  const saved={provider:'aladhan',locationMode:'manual',city:'A',country:'B',latitude:null,longitude:null};
  const schedule={coordinates:{latitude:41.0082,longitude:28.9784}};
  assert.deepEqual(Q.coordinates(saved,saved,schedule),schedule.coordinates);
  assert.equal(Q.coordinates({...saved,city:'Other'},saved,schedule),null);
  assert.equal(Q.coordinates({...saved,country:'Other'},saved,schedule),null);
  assert.equal(Q.coordinates({...saved,provider:'file'},saved,schedule),null);
  assert.equal(Q.coordinates({...saved,locationMode:'auto'},saved,schedule),null);
  const draft={...saved,latitude:0,longitude:0};
  assert.deepEqual(Q.coordinates(draft,saved,schedule),{latitude:0,longitude:0});
  assert.equal(Q.coordinates(saved,draft,schedule),null);
});
test('automatic and imported coordinates remain usable offline and respect the selected file',()=>{
  const auto={provider:'aladhan',locationMode:'auto'},coords={latitude:-6.2,longitude:106.8};
  assert.deepEqual(Q.coordinates(auto,auto,{coordinates:coords,locationMode:'auto'}),coords);
  assert.equal(Q.coordinates(auto,auto,{coordinates:coords,locationMode:'manual'}),null);
  const file={provider:'file',scheduleFile:'/old.json'};
  assert.deepEqual(Q.coordinates(file,file,{coordinates:coords}),coords);
  assert.equal(Q.coordinates({...file,scheduleFile:'/new.json'},file,{coordinates:coords}),null);
  assert.equal(Q.coordinates(file,file,{}),null);
});
