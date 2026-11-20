import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The evening behind the flock, drawn by a triangle over the whole frame:
// the sky's gradient (haze: the birds' aerial perspective too), the sun
// on the hills, a layer of cloud lit from below, three ridges of hills
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

// the sky along d (above the horizon) with what stands on it: the hills
// (their heights along d's bearing: far, middle, near), nearest last; cloud,
// its density along d
function land(d:Vec3, sun:Vec3, hills:Vec3, den:Float, mirrored:Bool):Vec3 {
	var c = haze(d, sun);
	var a = normalize(vec3(d.x, 0, d.z) + vec3(0.0001, 0, 0)).xz;
	var flat = haze(normalize(vec3(d.x, 0.004, d.z)), sun);
	// (cloud, a flat layer lit from below, thinning to the horizon)
	var cover = smoothstep(0.52, 0.72, den) * smoothstep(0.02, 0.14, d.y);
	var lit = pow(dot(a, normalize(sun.xz)) * 0.5 + 0.5, 3.0);
	var under = mix(vec3(0.07, 0.05, 0.09), vec3(2.2, 0.75, 0.3), lit) * (0.35 + 0.65 * smoothstep(0.8, 0.5, den));
	c = mix(c, under, cover * 0.92);
	if (!mirrored) c += vec3(40, 22, 9) * smoothstep(0.999962, 0.999972, dot(d, sun)) * (1 - cover);
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

// where along d the cloud layer is, in the cloud texture's units (it drifts)
function cloudAt(d:Vec3, time:Float):Vec2
	return d.xz * (1800 / max(d.y, 0.02)) * vec2(0.00018, 0.00045) * 0.25 + vec2(time * 0.0005, 0);

final SkyShader = shader({
	vertex: function(v:SkyVertex, p:{view:SkyView}):SkyVaryings
		return {pos: position(vec4(v.pos, 0, 1)), ray: p.view.forward.xyz + p.view.right.xyz * v.pos.x + p.view.up.xyz * v.pos.y},
	fragment: function(i:SkyVaryings, p:{view:SkyView, hills:Texture2D, clouds:Texture2D}):Vec4 {
		var d = normalize(i.ray);
		var sun = p.view.sun.xyz;
		var time = p.view.eye.w;
		if (d.y >= 0) {
			var uv = cloudAt(d, time);
			var den = sample(p.clouds, uv).x + 0.3 * sample(p.clouds, uv * 4.3 + vec2(0.31, 0.73)).x + 0.12 * sample(p.clouds, uv * 13.1 + vec2(0.7, 0.2)).x - 0.2;
			return vec4(land(d, sun, hillsAt(sample(p.hills, bearing(d)), d), den, false), 1);
		}
		// (the water: where the ray meets it, rippled; the sky in it by Fresnel)
		var t = p.view.eye.y / max(-d.y, 0.00001);
		var at = p.view.eye.xz + d.xz * t;
		var w = at * 0.08 + vec2(time * 0.05, time * 0.03);
		var ripple = vec2(noise(w) - 0.5, noise(w * 1.7 + vec2(5.2, 1.3)) - 0.5) * 0.06 * (1 / (1 + t * 0.002));
		var m = normalize(vec3(d.x + ripple.x * -d.y, -d.y, d.z + ripple.y * -d.y));
		var fresnel = 0.02 + 0.98 * pow(1 - m.y, 5.0);
		var uv = cloudAt(m, time);
		var den = sample(p.clouds, uv).x + 0.3 * sample(p.clouds, uv * 4.3 + vec2(0.31, 0.73)).x - 0.15;
		var c = land(m, sun, hillsAt(sample(p.hills, bearing(m)), m), den, true) * fresnel * 0.75 + vec3(0.004, 0.005, 0.009) * (1 - fresnel);
		var g = max(dot(normalize(vec3(d.x + ripple.x * 4, -d.y, d.z + ripple.y * 4)), sun), 0.0);
		c += SUN * pow(g, 600.0) * 6;
		var fog = 1 - exp(-t * FOG * 0.3);
		return vec4(mix(c, haze(normalize(vec3(d.x, 0.002, d.z)), sun), fog), 1);
	}
});
