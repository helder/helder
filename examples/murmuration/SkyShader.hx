import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The evening behind the flock, drawn by a triangle over the whole frame:
// the sky's gradient (haze: the birds' aerial perspective too), the sun
// on the hills, cloud lit from below, three ridges of hills
// fading with distance, and still water reflecting it all, its ripples
// glittering under the sun.
@:structInit @:publicFields class SkyVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class SkyVaryings {
	var pos:Vec4;
	var ray:Vec3;
}

@:structInit @:publicFields class SkyView {
	var right:Vec4; // scaled by the half width's tangent
	var up:Vec4; // by the half height's, w: angular pixel size
	var forward:Vec4;
	var eye:Vec4; // w: the time
	var sun:Vec4;
}

final ZENITH = vec3(0.022, 0.034, 0.09);
final HIGH = vec3(0.09, 0.07, 0.17);
final GLOW = vec3(1.5, 0.4, 0.11);
final ROSE = vec3(0.46, 0.2, 0.28);
final SHADOW = vec3(0.07, 0.07, 0.13);
final SUN = vec3(5.0, 2.3, 0.8);
final FOG = 0.0011;

function hash(p:Vec2):Float {
	var q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += vec3(dot(q, vec3(q.y, q.z, q.x) + vec3(33.33)));
	return fract((q.x + q.y) * q.z);
}

function noise(p:Vec2):Float {
	var i = floor(p), f = fract(p);
	var u = f * f * (vec2(3) - f * 2);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

function fbm(p:Vec2):Float {
	var s = 0.0, a = 0.5, x = p;
	for (k in 0...5) {
		s += a * noise(x);
		x = vec2(x.x * 1.6 - x.y * 1.2, x.x * 1.2 + x.y * 1.6) + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

// the sky's light along d without its sun or clouds: what distance fades towards
function haze(d:Vec3, sun:Vec3):Vec3 {
	var h = max(d.y, 0.0);
	var cs = dot(normalize(vec3(d.x, 0, d.z) + vec3(0.0001, 0, 0)), normalize(vec3(sun.x, 0, sun.z)));
	var toward = 0.5 + 0.5 * cs;
	var c = mix(ZENITH, HIGH, pow(1 - h, 3.0));
	var low = mix(ROSE, GLOW, toward * toward * toward);
	c = mix(c, low, pow(1 - h, 9.0));
	// (the earth's shadow rising opposite the sun, the rose band above it)
	var away = max(-cs, 0.0);
	c = mix(c, SHADOW, away * 0.8 * (1 - smoothstep(0.0, 0.06, h)));
	c += ROSE * 0.35 * away * smoothstep(0.03, 0.08, h) * (1 - smoothstep(0.08, 0.24, h));
	var m = max(dot(d, sun), 0.0);
	return c + SUN * (pow(m, 6.0) * 0.08 + pow(m, 60.0) * 0.35 + pow(m, 900.0) * 1.4);
}

// a ridge's height (a sine of elevation) along the horizon's direction
// (baked into a texture: SkyTextures)
function ridge(a:Vec2, scale:Float, seed:Float, base:Float, height:Float):Float
	return base + height * fbm(a * scale + vec2(seed, seed * 0.7));

function windAxes(p:Vec2):Vec2
	return vec2(dot(p, vec2(0.8, 0.6)) * 0.4, dot(p, vec2(-0.6, 0.8)));

function mipFor(footprint:Float):Float
	return log(max(1.0, footprint)) * 1.442695;

function cloudLayer(weather:Texture2D, uv:Vec2, sunward:Vec2, distance:Float, lod:Float, threshold:Float, light:Float):Vec4 {
	var field = sampleLevel(weather, uv, lod);
	var density = field.x - threshold - field.w * 0.125;
	var haze = exp(-distance * 0.00036);
	var thickness = max(density * 9.0, 0.0) * haze;
	var cover = (1 - exp(-thickness * 2.8)) * haze;
	var ahead = sampleLevel(weather, uv + sunward * 0.016, lod);
	var opticalDepth = max(0.0, ahead.x - threshold - ahead.w * 0.125) * 12.0;
	var transmission = exp(-opticalDepth - thickness * 0.55);
	var underside = mix(vec3(0.077, 0.067, 0.106), vec3(0.46, 0.18, 0.17), light);
	var amber = vec3(1.65, 0.62, 0.24) * light + vec3(0.074, 0.061, 0.079);
	var lining = vec3(1.5, 0.9, 0.59) * (light * transmission * transmission) * exp(-thickness * 5);
	return vec4((underside + amber * transmission + lining) * cover, cover);
}

function clouds(weather:Texture2D, d:Vec3, origin:Vec3, view:SkyView, mirrored:Bool):Vec4 {
	if (d.y < 0.025) return vec4(0);
	var sun = view.sun.xyz, time = view.eye.w;
	var low = (420 - origin.y) / d.y, high = (780 - origin.y) / d.y;
	var footprint = view.up.w * (mirrored ? 1.5 : 1.0) / d.y;
	var light = pow(dot(normalize(d.xz), sun.xz) * 0.5 + 0.5, 3.0);
	var sunward = windAxes(sun.xz);
	var a = cloudLayer(weather, windAxes(origin.xz + d.xz * high) / 290 + vec2(-time * 0.006 + 0.47, 0.71), sunward,
		high, mipFor(high * footprint * (SkyTextures.WEATHER_SIZE / 290)), 0.441, light);
	var b = cloudLayer(weather, windAxes(origin.xz + d.xz * low) / 410 + vec2(-time * 0.009 + 0.13, 0.23), sunward,
		low, mipFor(low * footprint * (SkyTextures.WEATHER_SIZE / 410)), 0.412, light);
	return b + a * (1 - b.w);
}

function land(weather:Texture2D, d:Vec3, hills:Vec3, origin:Vec3, view:SkyView, mirrored:Bool):Vec3 {
	var sun = view.sun.xyz;
	var c = haze(d, sun);
	var flat = haze(normalize(vec3(d.x, 0.004, d.z)), sun);
	var cloud = clouds(weather, d, origin, view, mirrored);
	c = c * (1 - cloud.w) + cloud.xyz;
	if (!mirrored) c += vec3(40, 22, 9) * smoothstep(0.999962, 0.999972, dot(d, sun)) * (1 - cloud.w);
	if (d.y < hills.x) c = mix(flat, vec3(0.05, 0.04, 0.07), 0.35);
	if (d.y < hills.y) c = mix(flat, vec3(0.02, 0.016, 0.03), 0.62);
	if (d.y < hills.z) c = mix(flat, vec3(0.006, 0.005, 0.008), 0.9);
	return c;
}

// the hills' heights along d's bearing (the texture's 0..1 back to sines),
// the near shore's wood crowned by a finer noise
function hillsAt(t:Vec4, d:Vec3):Vec3 {
	var a = normalize(vec3(d.x, 0, d.z) + vec3(0.0001, 0, 0)).xz;
	return t.xyz * 0.1 - vec3(0.02) + vec3(0, 0, 0.005 * smoothstep(0.35, 0.8, noise(a * 260)));
}

function bearing(d:Vec3):Vec2
	return vec2(atan2(d.z, d.x) / 6.2831853 + 0.5, 0.5);

final SkyShader = shader({
	vertex: function(v:SkyVertex, p:{view:SkyView}):SkyVaryings
		return {pos: position(vec4(v.pos, 0, 1)), ray: p.view.forward.xyz + p.view.right.xyz * v.pos.x + p.view.up.xyz * v.pos.y},
	fragment: function(i:SkyVaryings, p:{view:SkyView, hills:Texture2D, weather:Texture2D}):Vec4 {
		var d = normalize(i.ray);
		var sun = p.view.sun.xyz;
		var time = p.view.eye.w;
		if (d.y >= 0)
			return vec4(land(p.weather, d, hillsAt(sample(p.hills, bearing(d)), d), p.view.eye.xyz, p.view, false), 1);
		var t = p.view.eye.y / max(-d.y, 0.00001);
		var at = p.view.eye.xz + d.xz * t;
		var w = windAxes(at);
		var lod = mipFor(t * p.view.up.w * 6 / max(-d.y, 0.001));
		var a = sampleLevel(p.weather, w * 0.006 + vec2(time * 0.022, time * 0.017), lod).yz;
		var b = sampleLevel(p.weather, w.yx * 0.010 + vec2(-time * 0.031, time * 0.011), lod + 0.7).zy;
		var ripple = (a + b - vec2(1)) * (0.006 / (1 + t * 0.001));
		var normal = normalize(vec3(ripple.x, 1, ripple.y));
		var m = reflect(d, normal);
		var fresnel = 0.02 + 0.98 * pow(1 - clamp(dot(-d, normal), 0.0, 1.0), 5.0);
		var c = land(p.weather, m, hillsAt(sample(p.hills, bearing(m)), m), vec3(at.x, 0, at.y), p.view, true);
		c = mix(vec3(0.004, 0.005, 0.009), c * 0.82, fresnel);
		var g = max(dot(normalize(m + vec3(ripple.x, 0, ripple.y) * 5), sun), 0.0);
		c += SUN * pow(g, 600.0) * 6;
		var fog = 1 - exp(-t * FOG * 0.3);
		return vec4(mix(c, haze(normalize(vec3(d.x, 0.002, d.z)), sun), fog), 1);
	}
});
