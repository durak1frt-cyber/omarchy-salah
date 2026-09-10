#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec3 sunDirection;
    vec3 cameraFront;
    vec3 cameraEast;
    vec3 cameraNorth;
};
layout(binding = 1) uniform sampler2D landTexture;
void main() {
    vec2 p = vec2(qt_TexCoord0.x * 2.0 - 1.0, 1.0 - qt_TexCoord0.y * 2.0);
    float rr = dot(p,p);
    if (rr > 1.0) { fragColor = vec4(0.0); return; }
    float z = sqrt(max(0.0, 1.0-rr));
    vec3 normal = normalize(p.x*cameraEast + p.y*cameraNorth + z*cameraFront);
    float lon = atan(normal.y,normal.x);
    float lat = asin(clamp(normal.z,-1.0,1.0));
    float land = texture(landTexture, vec2(lon/6.28318530718+0.5,0.5-lat/3.14159265359)).r;
    vec3 ocean = vec3(0.0902,0.2235,0.2941);
    vec3 continent = vec3(0.5059,0.5961,0.5294);
    float light = dot(normal, normalize(sunDirection));
    float daylight = smoothstep(-0.08,0.10,light);
    vec3 day = mix(ocean,continent,land)*(0.72+0.28*max(light,0.0));
    vec3 night = mix(vec3(0.0706,0.1020,0.1686),vec3(0.18,0.235,0.275),land);
    vec3 color = mix(night,day,daylight);
    float twilight = exp(-pow(light*20.0,2.0));
    color += vec3(0.15,0.068,0.016)*twilight;
    float grid = min(abs(fract((lon+3.14159265359)/0.5235987756+0.5)-0.5), abs(fract((lat+1.57079632679)/0.5235987756+0.5)-0.5));
    color = mix(color,vec3(0.72,0.79,0.82),0.10*(1.0-smoothstep(0.003,0.01,grid)));
    color *= 0.70+0.30*z;
    float edge = 1.0-smoothstep(0.985,1.0,rr);
    fragColor = vec4(color*edge,edge)*qt_Opacity;
}
