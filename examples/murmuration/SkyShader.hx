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
	var up:Vec4; // by the half height's
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

function cloudDensity(p:Vec2, detail:Float):Float {
	var w = vec2(noise(p * 0.49), noise(p * 0.43 + vec2(4.6, 9.2))) - vec2(0.5);
	var q = p + w * 2.8;
	var r = vec2(q.x * 1.7 - q.y * 1.3, q.x * 1.3 + q.y * 1.7) + vec2(7.1, 3.5);
	return noise(q) * 0.57 + noise(r) * 0.26 + noise(r * 2.13 + vec2(2.8, 7.5)) * 0.17 * detail + 0.085 * (1 - detail);
}

function cloudLight(density:Float, light:Float):Vec3 {
	var thin = 1 - smoothstep(0.55, 0.77, density);
	var rim = smoothstep(0.52, 0.55, density) * (1 - smoothstep(0.55, 0.59, density));
	var cool = mix(vec3(0.052, 0.052, 0.092), vec3(0.15, 0.13, 0.21), thin);
	var warm = mix(vec3(0.29, 0.11, 0.12), vec3(1.9, 0.71, 0.28), thin);
	return mix(cool, warm, light) + vec3(1.8, 0.81, 0.42) * rim * light;
}

function clouds(d:Vec3, sun:Vec3, origin:Vec3, time:Float):Vec4 {
	var fade = smoothstep(0.07, 0.23, d.y);
	if (d.y <= 0.07) return vec4(0);
	var ray = d.xz / d.y;
	var high = (origin.xz + ray * (670 - origin.y)) / 360 + vec2(-time * 0.006, time * 0.003 + 31);
	var low = (origin.xz + ray * (390 - origin.y)) / 220 + vec2(-time * 0.012, time * -0.004);
	var a = cloudDensity(high, 0.7);
	var b = cloudDensity(low, 1.0);
	var back = smoothstep(0.52, 0.64, a) * fade * 0.58;
	var front = smoothstep(0.51, 0.62, b) * fade * 0.94;
	var light = pow(clamp(dot(d, sun) * 0.5 + 0.5, 0, 1), 5.0);
	return vec4(cloudLight(a, light) * back * (1 - front) + cloudLight(b, light) * front, back * (1 - front) + front);
}

function land(d:Vec3, sun:Vec3, hills:Vec3, origin:Vec3, time:Float, mirrored:Bool):Vec3 {
	var c = haze(d, sun);
	var flat = haze(normalize(vec3(d.x, 0.004, d.z)), sun);
	var cloud = clouds(d, sun, origin, time);
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
	fragment: function(i:SkyVaryings, p:{view:SkyView, hills:Texture2D}):Vec4 {
		var d = normalize(i.ray);
		var sun = p.view.sun.xyz;
		var time = p.view.eye.w;
		if (d.y >= 0)
			return vec4(land(d, sun, hillsAt(sample(p.hills, bearing(d)), d), p.view.eye.xyz, time, false), 1);
		// (the water: where the ray meets it, rippled; the sky in it by Fresnel)
		var t = p.view.eye.y / max(-d.y, 0.00001);
		var at = p.view.eye.xz + d.xz * t;
		var w = at * 0.08 + vec2(time * 0.05, time * 0.03);
		var ripple = vec2(noise(w) - 0.5, noise(w * 1.7 + vec2(5.2, 1.3)) - 0.5) * 0.06 * (1 / (1 + t * 0.002));
		var m = normalize(vec3(d.x + ripple.x * -d.y, -d.y, d.z + ripple.y * -d.y));
		var fresnel = 0.02 + 0.98 * pow(1 - m.y, 5.0);
		var c = land(m, sun, hillsAt(sample(p.hills, bearing(m)), m), vec3(at.x, 0, at.y), time, true) * fresnel * 0.75 + vec3(0.004, 0.005, 0.009) * (1 - fresnel);
		var g = max(dot(normalize(vec3(d.x + ripple.x * 4, -d.y, d.z + ripple.y * 4)), sun), 0.0);
		c += SUN * pow(g, 600.0) * 6;
		var fog = 1 - exp(-t * FOG * 0.3);
		return vec4(mix(c, haze(normalize(vec3(d.x, 0.002, d.z)), sun), fog), 1);
	}
});
