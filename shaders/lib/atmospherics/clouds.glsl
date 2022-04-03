void erodeCoord(inout vec2 coord, in float currentStep, in float erosionStrength){
	coord += cos(mix(vec2(cos(currentStep * 1.00), sin(currentStep * 2.00)), vec2(cos(currentStep * 3.0), sin(currentStep * 4.00)), currentStep) * erosionStrength);
}

#if defined PLANAR_CLOUDS && defined OVERWORLD
float CloudNoise(vec2 coord, vec2 wind){

	float windMult = 0.5;
	float frequencyMult = 0.25;
	float noiseMult = 1.0;
	float noise = 0.0;

	for (int i = 0; i < CLOUD_OCTAVES; i++){
		noise += texture2D(noisetex, coord * frequencyMult + wind * windMult).x * noiseMult;
		windMult *= 0.75;
		frequencyMult *= CLOUD_FREQUENCY;
		noiseMult += 1.0;
	}

	return noise;
}

float CloudCoverage(float noise, float VoU, float coverage){
	float noiseMix = mix(noise, 21.0, 0.33 * rainStrength);
	float noiseFade = clamp(sqrt(VoU * 10.0), 0.0, 1.0);
	float noiseCoverage = (coverage * coverage) + CLOUD_AMOUNT;
	float multiplier = 1.0 - 0.5 * rainStrength;

	return max(noiseMix * noiseFade - noiseCoverage, 0.0) * multiplier;
}

vec4 DrawCloud(vec3 viewPos, float dither, vec3 lightCol, vec3 ambientCol){
	float VoS = dot(normalize(viewPos), sunVec);
	float VoU = dot(normalize(viewPos), upVec);
	
	#ifdef TAA
	dither = fract(16.0 * frameTimeCounter + dither);
	#endif

	float cloud = 0.0;
	float cloudGradient = 0.0;
	float colorMultiplier = CLOUD_BRIGHTNESS * (0.5 - 0.25 * (1.0 - sunVisibility) * (1.0 - rainStrength));
	float gradientMix = dither * 0.1667;
	float noiseMultiplier = CLOUD_THICKNESS * 0.2;
	float scattering = pow(VoS * 0.5 * (2.0 * sunVisibility - 1.0) + 0.5, 6.0);

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.001,
		sin(frametime * CLOUD_SPEED * 0.05) * 0.002
	) * CLOUD_HEIGHT / 15.0;

	vec3 cloudColor = vec3(0.0);

	if (VoU > 0.1){
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < 6; i++) {
			vec3 planeCoord = wpos * ((CLOUD_HEIGHT + (i + dither) * 0.75) / wpos.y) * 0.02;
			vec2 coord = cameraPosition.xz * 0.001 + planeCoord.xz;
				 erodeCoord(coord, i + dither, 0.015);
				#ifdef BLOCKY_CLOUDS
				coord = floor(coord * 8.0);
				#endif
			float coverage = float(i - 3.0 + dither) * 0.667;

			float noise = CloudNoise(coord, wind);
				  noise = CloudCoverage(noise, VoU, coverage) * noiseMultiplier;
				  noise = noise / pow(pow(noise, 2.5) + 1.0, 0.4);

			cloudGradient = mix(
				cloudGradient,
				mix(gradientMix * gradientMix, 1.0 - noise, 0.25),
				noise * (1.0 - cloud * cloud)
			);

			cloud = mix(cloud, 1.0, noise);
			gradientMix += 0.1667;
		}
		cloudColor = mix(
			ambientCol * (0.5 * sunVisibility + 0.5),
			lightCol * (1.0 + scattering + rainStrength),
			cloudGradient * cloud
		);

		#if MC_VERSION >= 11800
		cloudColor *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
		#else
		cloudColor *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
		#endif
		
		#ifdef UNDERGROUND_SKY
		cloud *= mix(clamp((cameraPosition.y - 48.0) / 16.0, 0.0, 1.0), 1.0, eBS);
		#endif

		cloudColor *= 1.0 - 0.6 * rainStrength;
		cloud *= sqrt(sqrt(clamp(VoU * 10.0 - 1.0, 0.0, 1.0))) * (1.0 - 0.6 * rainStrength);
	}

	return vec4(cloudColor * colorMultiplier, cloud * cloud * CLOUD_OPACITY);
}
#endif

float GetNoise(vec2 pos) {
	return fract(sin(dot(pos, vec2(12.9898, 4.1414))) * 43758.5453);
}

void DrawStars(inout vec3 color, vec3 viewPos, float size, float amount, float brightness) {
	vec3 wpos = vec3(gbufferModelViewInverse * vec4(viewPos, 1.0));
	vec3 planeCoord = wpos / (wpos.y + length(wpos.xz));

	vec2 wind = vec2(frametime, 0.0);
	vec2 coord = planeCoord.xz * size + cameraPosition.xz * 0.000001 + wind * 0.001;
		 coord = floor(coord * 1024.0) / 1024.0;
	
	float VoU = clamp(dot(normalize(viewPos), upVec), 0.0, 1.0);

	#ifdef END
	VoU = 1.0;
	#endif

	float multiplier = VoU * 16.0 * (1.0 - rainStrength) * (1.0 - sunVisibility * 0.5);
	
	float star = GetNoise(coord.xy);
		  star*= GetNoise(coord.xy + 0.10);
		  star*= GetNoise(coord.xy + 0.23);
	star *= amount;
	star = clamp(star - 0.75, 0.0, 1.0) * multiplier;

	#ifdef OVERWORLD

	#if MC_VERSION >= 11800
	star *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	star *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif

	#ifdef UNDERGROUND_SKY
	star *= mix(clamp((cameraPosition.y - 48.0) / 16.0, 0.0, 1.0), 1.0, eBS);
	#endif
	
	#endif

	color += star * vec3(0.5, 0.75, 1.00) * brightness * (1.0 - timeBrightness * 0.75);
}

#ifdef AURORA
#include "/lib/color/auroraColor.glsl"

float AuroraSample(vec2 coord, vec2 wind) {
	float noise = texture2D(noisetex, coord * 0.04 + wind * 0.25).b * 3.0;
		  noise+= texture2D(noisetex, coord * 0.02 + wind * 0.15).b * 3.0;

	noise = max(1.0 - 2.0 * abs(noise - 3.0), 0.0);

	return noise;
}

vec3 DrawAurora(vec3 viewPos, float dither, int samples) {
	#ifdef TAA
	dither = fract(16.0 * frameTimeCounter + dither);
	#endif
	
	float VoU = dot(normalize(viewPos.xyz), upVec);

	float sampleStep = 1.0 / samples;
	float currentStep = dither * sampleStep;

	float visibility = moonVisibility * (1.0 - rainStrength) * (1.0 - rainStrength);

	#ifdef WEATHER_PERBIOME
	visibility *= isCold * isCold;
	#endif

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.00025,
		sin(frametime * CLOUD_SPEED * 0.05) * 0.0005
	);

	vec3 aurora = vec3(0.0);

	if (visibility > 0.0 && VoU > 0.0) {
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < samples; i++) {
			vec3 planeCoord = wpos * ((6.0 + currentStep * 16.0) / wpos.y) * 0.003;

			vec2 coord = cameraPosition.xz * 0.00004 + planeCoord.xz;
			coord += vec2(coord.y, -coord.x) * 0.6;

			float noise = AuroraSample(coord, wind);
			
			if (noise > 0.0) {
				noise *= texture2D(noisetex, coord * 0.125 + wind * 0.25).b;
				noise *= texture2D(noisetex, coord + wind * 16.0).b * 0.5 + 0.75;
				noise = noise * noise * 3.0 * sampleStep;
				noise *= max(sqrt(1.0 - length(planeCoord.xz) * 3.0), 0.0);

				vec3 auroraColor = mix(auroraLowCol, auroraHighCol, pow(currentStep, 0.4));
				aurora += noise * auroraColor * exp2(-6.0 * i * sampleStep);
			}
			currentStep += sampleStep;
		}
	}

	#if MC_VERSION >= 11800
	visibility *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	visibility *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif

	#ifdef UNDERGROUND_SKY
	visibility *= mix(clamp((cameraPosition.y - 48.0) / 16.0, 0.0, 1.0), 1.0, eBS);
	#endif

	return aurora * visibility;
}
#endif

#if defined END_NEBULA || defined OVERWORLD_NEBULA
#include "/lib/color/nebulaColor.glsl"

float nebulaSample(vec2 coord, vec2 wind, float VoU) {
	float noise = texture2D(noisetex, coord * 1.0000 - wind * 0.25).b * 2.5;
		  noise-= texture2D(noisetex, coord * 0.5000 + wind * 0.20).b * 1.5;
		  noise+= texture2D(noisetex, coord * 0.2500 - wind * 0.15).b * 3.0;
		  noise+= texture2D(noisetex, coord * 0.1250 + wind * 0.10).b * 3.5;

	noise *= NEBULA_AMOUNT;
	
	#ifdef END
	noise *= 1.1;
	#endif

	noise = max(1.0 - 2.0 * (0.5 * VoU + 0.5) * abs(noise - 3.5), 0.0);

	return noise;
}

float InterleavedGradientNoise1() {
	float n = 52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y);

	return fract(n);
}

vec3 DrawNebula(vec3 viewPos) {
	#ifdef OVERWORLD
	int samples = 4;
	#else
	int samples = 6;
	#endif

	float dither = InterleavedGradientNoise1();

	#ifdef TAA
	dither = fract(16.0 * frameTimeCounter + dither);
	#endif

	float VoU = dot(normalize(viewPos.xyz), upVec);

	#ifdef END
	VoU = abs(VoU);
	#endif

	float visFactor = 1.0;

	#ifdef OVERWORLD
	float auroraVisibility = 0.0;

	#ifdef NEBULA_AURORA_CHECK
	#if defined AURORA && defined WEATHER_PERBIOME && defined OVERWORLD
	auroraVisibility = isCold * isCold;
	#endif
	#endif

	visFactor = (moonVisibility - rainStrength) * (moonVisibility - auroraVisibility) * (1.0 - auroraVisibility);
	#endif

	float sampleStep = 1.0 / samples;
	float currentStep = dither * sampleStep;

	vec2 wind = vec2(
		frametime * NEBULA_SPEED * 0.000125,
		sin(frametime * NEBULA_SPEED * 0.05) * 0.00125
	);

	vec3 nebula = vec3(0.0);
	vec3 nebulaColor = vec3(0.0);

	#ifdef END
	if (visFactor > 0){
	#else
	if (visFactor > 0 && VoU > 0){
	#endif
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < samples; i++) {
			#ifdef END
			vec3 planeCoord = wpos * (16.0 + currentStep * -8.0) * 0.001 * NEBULA_STRETCHING;
			#else
			vec3 planeCoord = wpos * ((6.0 + currentStep * -2.0) / wpos.y) * 0.005 * NEBULA_STRETCHING;
			#endif

			vec2 coord = (cameraPosition.xz * 0.000005 + planeCoord.xz);

			#ifdef END
			coord += vec2(coord.y, -coord.x) * 1.00 * NEBULA_DISTORTION;
			#endif

			erodeCoord(coord, currentStep, 0.1);
			erodeCoord(coord, currentStep, 0.2);

			float noise = nebulaSample(coord, wind, VoU);
				 noise *= texture2D(noisetex, coord * 0.25 + wind * 0.25).r;
				 noise *= texture2D(noisetex, coord + wind * 16.0).r + 0.75;
				 noise = noise * noise * 2.0 * sampleStep;
				 noise *= max(sqrt(1.0 - length(planeCoord.xz) * 4.0), 0.0);

			#if defined END
			nebulaColor = mix(vec3(endCol.r, endCol.g, endCol.b * 1.5) * 4.0, vec3(endCol.r * 2.0, endCol.g, endCol.b) * 16.0, currentStep);
			#elif defined OVERWORLD
			nebulaColor = mix(nebulaLowCol, nebulaHighCol, currentStep);
			#endif

			nebula += noise * nebulaColor * exp2(-4.0 * i * sampleStep);
			currentStep += sampleStep;
		}
	}

	#if defined UNDERGROUND_SKY && defined OVERWORLD
	nebula *= mix(clamp((cameraPosition.y - 48.0) / 16.0, 0.0, 1.0), 1.0, eBS);
	#endif

	return nebula * NEBULA_BRIGHTNESS * visFactor;
}
#endif