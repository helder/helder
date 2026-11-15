import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PostShader.viewDepthAt;
import helder.scene.render.EffectShaders.octDecode;

// The poststage frame's own stages (Scenes, PostProcess.add): a sepia
// grade, then scanlines (bands of 8 pixels, the image read Nearest by its
// pixels: the fragment's position), the last into the frame
@:structInit @:publicFields class StageVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class StageVaryings {
	var clip:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class StageParams {
	var size:Vec4; // xy: the image's pixels, z: a band's pixels, w: the sepia's share
}

function fullscreen(v:StageVertex):StageVaryings
	return {clip: position(vec4(v.pos, 0, 1)), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

final SepiaShader = shader({
	vertex: function(v:StageVertex):StageVaryings return fullscreen(v),
	fragment: function(i:StageVaryings, p:{stage:StageParams, image:Texture2D}):Vec4 {
		var c = sample(p.image, i.uv);
		var y = dot(c.xyz, vec3(0.3, 0.59, 0.11));
		return vec4(mix(c.xyz, vec3(y * 1.1, y * 0.9, y * 0.7), p.stage.size.w), c.w);
	}
});

final ScanShader = shader({
	vertex: function(v:StageVertex):StageVaryings return fullscreen(v),
	fragment: function(i:StageVaryings, p:{stage:StageParams, image:Texture2D}):Vec4 {
		var c = sample(p.image, i.clip.xy / p.stage.size.xy);
		var dark = fract(i.clip.y / p.stage.size.z) < 0.5 ? 1.0 : 0.55;
		return vec4(c.xyz * dark, c.w);
	}
});

// the prepass frame's view of the view buffers (Scenes' prepass,
// ViewBuffers): their depth on the left (the distance, near light, far
// dark), the normals on the right (view space, as colours), the selection
// group tinting both
@:structInit @:publicFields class ViewsParams {
	var inverseProjection:Mat4;
	var far:Vec4; // x: the distance shown darkest
}

final ViewsShader = shader({
	vertex: function(v:StageVertex):StageVaryings return fullscreen(v),
	fragment: function(i:StageVaryings, p:{views:ViewsParams, depth:Texture2D, normals:Texture2D}):Vec4 {
		var d = sampleLevel(p.depth, i.uv, 0).x;
		var t = sampleLevel(p.normals, i.uv, 0);
		var c = vec3(0.05, 0.05, 0.08);
		if (d < 0.99999) {
			if (i.uv.x < 0.5) {
				var z = viewDepthAt(p.views.inverseProjection, i.uv, d);
				c = vec3(1 - clamp(z / p.views.far.x, 0, 1));
			} else
				c = octDecode(t.xy) * 0.5 + 0.5;
			if (t.w > 0.002) c = mix(c, vec3(1, 0.3, 0.6), 0.35);
		}
		return vec4(c, 1);
	}
});

// (debugging: a texture's red, shown over the frame: EffectScenes' HXMC_SHOW=ao)
final ShowShader = shader({
	vertex: function(v:StageVertex):StageVaryings return fullscreen(v),
	fragment: function(i:StageVaryings, p:{image:Texture2D}):Vec4 {
		return vec4(vec3(sampleLevel(p.image, i.uv, 0).x), 1);
	}
});
