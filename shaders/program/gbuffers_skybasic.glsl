/* 
BSL Shaders v8 Series by Capt Tatsu 
https://bitslablab.com 
*/ 

//Settings//
#include "/lib/settings.glsl"

//Fragment Shader///////////////////////////////////////////////////////////////////////////////////
#ifdef FSH

//Varyings//
varying float star;

varying vec3 upVec, sunVec;

//Uniforms//
uniform int isEyeInWater;
uniform int worldTime;

#ifdef RAINBOW
uniform float wetness;
#endif

uniform float blindFactor;
uniform float frameCounter;
uniform float frameTimeCounter;
uniform float nightVision;
uniform float rainStrength;
uniform float shadowFade, voidFade;
uniform float timeAngle, timeBrightness;
uniform float viewWidth, viewHeight, aspectRatio;

uniform ivec2 eyeBrightnessSmooth;

uniform vec3 cameraPosition;

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse, gbufferProjection;

uniform sampler2D noisetex;

//Common Variables//
#ifdef WORLD_TIME_ANIMATION
float frametime = float(worldTime) * 0.05 * ANIMATION_SPEED;
#else
float frametime = frameTimeCounter * ANIMATION_SPEED;
#endif

float eBS = eyeBrightnessSmooth.y / 240.0;
float sunVisibility  = clamp((dot( sunVec, upVec) + 0.05) * 10.0, 0.0, 1.0);
float moonVisibility = clamp((dot(-sunVec, upVec) + 0.05) * 10.0, 0.0, 1.0);

vec3 lightVec = sunVec * (1.0 - 2.0 * float(timeAngle > 0.5325 && timeAngle < 0.9675));

//Common Functions//
float GetLuminance(vec3 color) {
	return dot(color,vec3(0.299, 0.587, 0.114));
}

void RoundSunMoon(inout vec3 color, vec3 viewPos, vec3 sunColor, vec3 moonColor) {
	float VoL = dot(normalize(viewPos), sunVec);
	float isMoon = float(VoL < 0.0);
	float sun = pow(abs(VoL), 800.0 * isMoon + 800.0) * (1.0 - sqrt(rainStrength));

	vec3 sunMoonCol = mix(moonColor * moonVisibility, sunColor * sunVisibility, float(VoL > 0.25));

	#if MC_VERSION >= 11800
	sunMoonCol *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	sunMoonCol *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif
	
	color += sun * sunMoonCol;
}

void SunGlare(inout vec3 color, vec3 viewPos, vec3 lightCol) {
	float VoL = dot(normalize(viewPos), lightVec);
	float visfactor = 0.05 * (-0.8 * timeBrightness + 1.0) * (3.0 * rainStrength + 1.0);
	float invvisfactor = 1.0 - visfactor;

	float visibility = clamp(VoL * 0.5 + 0.5, 0.0, 1.0);
    visibility = visfactor / (1.0 - invvisfactor * visibility) - visfactor;
	visibility = clamp(visibility * 1.015 / invvisfactor - 0.015, 0.0, 1.0);
	visibility = mix(1.0, visibility, 0.25 * eBS + 0.75) * (1.0 - rainStrength * eBS * 0.875);
	visibility *= shadowFade * 0.25;

	#if MC_VERSION >= 11800
	visibility *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	visibility *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif

	color += lightCol * visibility * (1.0 + 0.25 * isEyeInWater);
}

//Includes//
#include "/lib/color/dimensionColor.glsl"
#include "/lib/color/skyColor.glsl"
#include "/lib/util/dither.glsl"
#if (defined OVERWORLD && defined PLANAR_CLOUDS) || defined OVERWORLD_NEBULA || defined STARS || defined AURORA
#include "/lib/atmospherics/clouds.glsl"
#endif
#include "/lib/atmospherics/sky.glsl"

#if defined OVERWORLD && defined MOON_SMOKE
vec3 GetSmoke(vec3 viewPos) {
	float VoL = dot(normalize(viewPos.xyz), -sunVec);
	float halfVoL = VoL * shadowFade * 0.5 + 0.5;
	float visibility = pow16(halfVoL) * (1.0 - rainStrength) * (1.0 - timeBrightness);

	vec3 wpos = mat3(gbufferModelViewInverse) * viewPos;
	vec2 planeCoord = wpos.xz / (wpos.y + length(wpos.xz) * 0.5);

	float smokeNoise = texture2D(noisetex, planeCoord * 0.075).r * 0.1;
		  smokeNoise+= texture2D(noisetex, planeCoord * 0.050).r * 0.2;
		  smokeNoise+= texture2D(noisetex, planeCoord * 0.025).r * 0.3;

	vec3 smoke = smokeNoise * lightNight * visibility;

	return smoke * MOON_SMOKE_BRIGHTNESS * MOON_SMOKE_BRIGHTNESS;
}
#endif

#ifdef RAINBOW
vec3 RainbowLens(vec3 viewPos, vec2 lightPos, float size, float dist, float rad) {
	vec3 wpos = mat3(gbufferModelViewInverse) * viewPos;

	vec3 planeCoord = wpos / (wpos.y + length(wpos.xz) * 0.5);
	vec2 lensCoord = planeCoord.xz + vec2(2.5, 0.0);

	float VoU = dot(normalize(viewPos), upVec);
	float lens = clamp(1.0 - length(lensCoord) / size, 0.0, 1.0);
	
	vec3 rainbowLens = 
		(smoothstep(0.0, rad, lens) - smoothstep(rad, rad * 2.0, lens)) * vec3(1.0, 0.0, 0.0) +
		(smoothstep(rad * 0.5, rad * 1.5, lens) - smoothstep(rad * 1.5, rad * 2.5, lens)) * vec3(0.0, 1.0, 0.0) +
		(smoothstep(rad, rad * 2.0, lens) - smoothstep(rad * 2.0, rad * 3.0, lens)) * vec3(0.0, 0.0, 1.0)
	;

	return rainbowLens * float(VoU > 0.0) * wetness * (1.0 - rainStrength);
}
#endif

//Program//
void main() {
	vec4 screenPos = vec4(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z, 1.0);
	vec4 viewPos = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
	viewPos /= viewPos.w;
	
	vec3 albedo = GetSkyColor(viewPos.xyz, false);

	#ifdef RAINBOW
	albedo += RainbowLens(viewPos.xyz, viewPos.xy, 1.5, -0.5, 0.05) * 0.1;
	#endif

	#if defined OVERWORLD && defined MOON_SMOKE
	albedo += GetSmoke(viewPos.xyz);
	#endif

	#ifdef ROUND_SUN_MOON
	vec3 lightMA = mix(lightMorning, lightEvening, mefade);
    vec3 sunColor = mix(lightMA, sqrt(lightDay * lightMA * LIGHT_DI), timeBrightness);
    vec3 moonColor = sqrt(lightNight);

	RoundSunMoon(albedo, viewPos.xyz, sunColor, moonColor);
	#endif

	#ifdef STARS
	DrawStars(albedo.rgb, viewPos.xyz, 0.2, 0.9, 1.5);
	DrawStars(albedo.rgb, viewPos.xyz, 0.35, 1.0, 0.75);
	#endif

	float dither = Bayer64(gl_FragCoord.xy);

	#ifdef AURORA
	albedo.rgb += DrawAurora(viewPos.xyz, dither, 16);
	#endif
	
	#ifdef OVERWORLD_NEBULA
	albedo.rgb += DrawNebula(viewPos.xyz);
	#endif

	#if defined PLANAR_CLOUDS
	vec4 cloud = DrawCloud(viewPos.xyz, dither, lightCol, ambientCol);
	albedo.rgb = mix(albedo.rgb, cloud.rgb, cloud.a);
	#endif

	albedo.rgb *= (4.0 - 3.0 * eBS) * (1.0 + nightVision);

	#if ALPHA_BLEND == 0
	albedo.rgb = sqrt(max(albedo.rgb, vec3(0.0)));
	albedo.rgb = albedo.rgb + dither / vec3(64.0);
	#endif
	
    /* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(albedo, 1.0 - star);
    #if defined OVERWORLD && defined PLANAR_CLOUDS
    /* DRAWBUFFERS:04 */
	gl_FragData[1] = vec4(cloud.a, 0.0, 0.0, 0.0);
    #endif
}

#endif

//Vertex Shader/////////////////////////////////////////////////////////////////////////////////////
#ifdef VSH

//Varyings//
varying float star;

varying vec3 sunVec, upVec;

//Uniforms//
uniform float timeAngle;

uniform mat4 gbufferModelView;

//Program//
void main() {
	const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
	float ang = fract(timeAngle - 0.25);
	ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;
	sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);

	upVec = normalize(gbufferModelView[1].xyz);
	
	gl_Position = ftransform();

	star = float(gl_Color.r == gl_Color.g && gl_Color.g == gl_Color.b && gl_Color.r > 0.0);
}

#endif