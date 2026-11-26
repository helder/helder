package helder.scene.view;

import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.render.PostProcess;
import helder.scene.render.ToneMap;
import helder.scene.view.SceneRenderer.SceneNode;
import helder.view.Render;
import helder.view.graph.Graph;
import helder.view.graph.Read;

// A <Scene>'s post effects in markup (import helder.scene.view.EffectTags.*),
// configuration of its box, not scene nodes: <Effects> sets its post
// chain's own values (the box turned hdr), the effects in it are set on the
// chain while they are there (and unset when they go):
//
//   <Scene flexGrow={1}>
//     <Effects bloom={0.05} toneMap={AgX}>
//       <Ssao radius={0.5} samples={8}/>
//       <Dof tiltShift band={0.2}/>
//       <Outline width={2} color={gold}/>
//       <Fxaa/>                     // or <Smaa/>, <Taa blend={0.1}/>
//       <Ssr maxDistance={8}/> <MotionBlur strength={0.5}/> <GodRays intensity={0.5}/>
//     </Effects>
//     <node outline={hovered.value ? 1 : 0}>...</node>   // Outline.select, as data
//   </Scene>
//
// Each tag is a function whose props are the effect's options, typed: a typo
// is a compile error, and an effect never named is not linked. A prop
// bound to a signal follows it (the effect's field set, nothing made
// again). The tags are capitalized (components): an element's props are
// set by name at run time, and would link every effect.
// Their names are the effects' classes': where both are imported, write
// the class's path (helder.scene.render.Outline.select).
class EffectTags {
	// the chain's own values; its children the effects
	public static function Effects(props:{
		?bloom:Read<Float>,
		?toneMap:ToneMap,
		?exposure:Read<Float>,
		?saturation:Read<Float>,
		?contrast:Read<Float>,
		?vignette:Read<Float>,
		?grain:Read<Float>,
		?levels:Int,
		?base:Int,
		?children:SceneView
	}):SceneNode {
		var box = boxOf("Effects");
		if (props.toneMap != null) {
			var t = props.toneMap;
			box.withPost(p -> p.toneMap = t);
		}
		if (props.levels != null) {
			var n:Int = props.levels;
			box.withPost(p -> p.levels = n);
		}
		if (props.base != null) {
			var n:Int = props.base;
			box.withPost(p -> p.base = n);
		}
		number(box, props.bloom, (p, v) -> p.bloom = v);
		number(box, props.exposure, (p, v) -> p.exposure = v);
		number(box, props.saturation, (p, v) -> p.saturation = v);
		number(box, props.contrast, (p, v) -> p.contrast = v);
		number(box, props.vignette, (p, v) -> p.vignette = v);
		number(box, props.grain, (p, v) -> p.grain = v);
		var marker = SceneRenderer.createMarker("effects");
		Render.insert(props.children, marker, null);
		return marker;
	}

	// screen-space ambient occlusion (helder.scene.render.Ssao: GTAO)
	public static function Ssao(props:{?radius:Read<Float>, ?intensity:Read<Float>, ?samples:Int, ?slices:Int, ?halfRes:Bool}):SceneNode {
		var box = boxOf("Ssao");
		var ao = new helder.scene.render.Ssao({samples: props.samples, slices: props.slices, halfRes: props.halfRes});
		number(box, props.radius, (_, v) -> ao.radius = v);
		number(box, props.intensity, (_, v) -> ao.intensity = v);
		return effect(box, "ssao", p -> p.ao = ao, p -> if (p.ao == ao) p.ao = null);
	}

	// depth of field (helder.scene.render.Dof): a lens focused at distance
	// (aperture), or with tiltShift a diorama's (band, falloff, strength)
	public static function Dof(props:{
		?tiltShift:Bool,
		?distance:Read<Float>,
		?aperture:Read<Float>,
		?band:Read<Float>,
		?falloff:Read<Float>,
		?strength:Read<Float>,
		?radius:Read<Float>,
		?center:Read<Float>,
		?samples:Int
	}):SceneNode {
		var box = boxOf("Dof");
		var dof = props.tiltShift == true ? helder.scene.render.Dof.tiltShift({samples: props.samples}) : helder.scene.render.Dof.focus({distance: 5, samples: props.samples});
		number(box, props.distance, (_, v) -> dof.distance = v);
		number(box, props.aperture, (_, v) -> dof.aperture = v);
		number(box, props.band, (_, v) -> dof.band = v);
		number(box, props.falloff, (_, v) -> dof.falloff = v);
		number(box, props.strength, (_, v) -> dof.strength = v);
		number(box, props.radius, (_, v) -> dof.radius = v);
		number(box, props.center, (_, v) -> dof.center = v);
		return effect(box, "dof", p -> p.dof = dof, p -> if (p.dof == dof) p.dof = null);
	}

	// the selection's outlines (helder.scene.render.Outline): group 1's
	// width and colour; nodes selected by their outline prop (<node
	// outline={1}>) or Outline.select
	public static function Outline(props:{?width:Read<Float>, ?color:Read<Vec4>}):SceneNode {
		var box = boxOf("Outline");
		var o = new helder.scene.render.Outline();
		number(box, props.width, (_, v) -> o.width = v);
		if (props.color != null) {
			var v:Dynamic = props.color;
			if (Render.isReactive(v)) Graph.renderEffect(() -> (Render.read(v) : Dynamic), (c:Dynamic) -> {
				o.color = c;
				box.onPost(_ -> {});
			}) else
				o.color = Render.read(v);
		}
		return effect(box, "outline", p -> p.outline = o, p -> if (p.outline == o) p.outline = null);
	}

	// FXAA in the composite (post.antialias Fxaa)
	public static function Fxaa(props:{}):SceneNode {
		var box = boxOf("Fxaa");
		return effect(box, "fxaa", p -> p.antialias = helder.scene.render.Antialias.Fxaa, p -> p.antialias = helder.scene.render.Antialias.None);
	}

	// SMAA (helder.scene.render.Smaa): edges and their blending weights,
	// blended in the composite
	public static function Smaa(props:{?threshold:Read<Float>}):SceneNode {
		var box = boxOf("Smaa");
		var smaa = new helder.scene.render.Smaa();
		number(box, props.threshold, (_, v) -> smaa.threshold = v);
		return effect(box, "smaa", p -> p.smaa = smaa, p -> if (p.smaa == smaa) p.smaa = null);
	}

	// temporal antialiasing (helder.scene.render.Taa): the frame jittered,
	// gathered with its history; blend the new frame's share
	public static function Taa(props:{?blend:Read<Float>}):SceneNode {
		var box = boxOf("Taa");
		var taa = new helder.scene.render.Taa();
		number(box, props.blend, (_, v) -> taa.blend = v);
		return effect(box, "taa", p -> p.taa = taa, p -> if (p.taa == taa) p.taa = null);
	}

	// screen-space reflections (helder.scene.render.Ssr)
	public static function Ssr(props:{
		?intensity:Read<Float>,
		?maxDistance:Read<Float>,
		?thickness:Read<Float>,
		?maxRoughness:Read<Float>,
		?steps:Int,
		?halfRes:Bool
	}):SceneNode {
		var box = boxOf("Ssr");
		var ssr = new helder.scene.render.Ssr({steps: props.steps, halfRes: props.halfRes});
		number(box, props.intensity, (_, v) -> ssr.intensity = v);
		number(box, props.maxDistance, (_, v) -> ssr.maxDistance = v);
		number(box, props.thickness, (_, v) -> ssr.thickness = v);
		number(box, props.maxRoughness, (_, v) -> ssr.maxRoughness = v);
		return effect(box, "ssr", p -> p.ssr = ssr, p -> if (p.ssr == ssr) p.ssr = null);
	}

	// motion blur (helder.scene.render.MotionBlur): the camera's, or with
	// objects each object's too
	public static function MotionBlur(props:{?strength:Read<Float>, ?max:Read<Float>, ?samples:Int, ?objects:Bool}):SceneNode {
		var box = boxOf("MotionBlur");
		var blur = new helder.scene.render.MotionBlur({samples: props.samples, objects: props.objects});
		number(box, props.strength, (_, v) -> blur.strength = v);
		number(box, props.max, (_, v) -> blur.max = v);
		return effect(box, "motion-blur", p -> p.motionBlur = blur, p -> if (p.motionBlur == blur) p.motionBlur = null);
	}

	// god rays (helder.scene.render.GodRays): the sky's light towards the sun
	public static function GodRays(props:{
		?intensity:Read<Float>,
		?density:Read<Float>,
		?decay:Read<Float>,
		?falloff:Read<Float>,
		?samples:Int
	}):SceneNode {
		var box = boxOf("GodRays");
		var rays = new helder.scene.render.GodRays({samples: props.samples});
		number(box, props.intensity, (_, v) -> rays.intensity = v);
		number(box, props.density, (_, v) -> rays.density = v);
		number(box, props.decay, (_, v) -> rays.decay = v);
		number(box, props.falloff, (_, v) -> rays.falloff = v);
		return effect(box, "god-rays", p -> p.godRays = rays, p -> if (p.godRays == rays) p.godRays = null);
	}

	// colour grading by a table (helder.scene.render.Lut): of (made by the
	// program), an image (a size cubed strip: 256 x 16), or a grade (display
	// values in and out) made into a 16 cubed table on the box's device
	public static function Lut(props:{
		?of:helder.scene.render.Lut,
		?image:helder.image.Image,
		?grade:(r:Float, g:Float, b:Float) -> Vec3,
		?strength:Read<Float>
	}):SceneNode {
		var box = boxOf("Lut");
		var made:Null<helder.scene.render.Lut> = props.of;
		var strength = 1.0;
		function lut(p:PostProcess):Null<helder.scene.render.Lut> {
			if (made == null && props.image != null) made = helder.scene.render.Lut.fromImage(p.device, props.image);
			if (made == null && props.grade != null) made = helder.scene.render.Lut.of(p.device, 16, props.grade);
			if (made != null) made.strength = strength;
			return made;
		}
		number(box, props.strength, (_, v) -> {
			strength = v;
			if (made != null) made.strength = v;
		});
		return effect(box, "lut", p -> p.lut = lut(p), p -> if (p.lut == made) p.lut = null);
	}

	static function boxOf(tag:String):SceneBox {
		var box = Graph.use(SceneTags.BOX);
		if (box == null) throw 'helder.scene: <$tag> is in a <Scene>\'s markup';
		return box;
	}

	// (an effect set on the chain while its tag is there, unset after)
	static function effect(box:SceneBox, name:String, set:PostProcess->Void, unset:PostProcess->Void):SceneNode {
		var on = true;
		box.withPost(p -> if (on) set(p));
		Graph.onCleanup(() -> {
			on = false;
			box.onPost(unset);
		});
		return SceneRenderer.createMarker(name);
	}

	// (a number prop, its value or a signal's: f with the chain and it, now
	// and at each change)
	static function number(box:SceneBox, prop:Null<Read<Float>>, f:(PostProcess, Float) -> Void) {
		if (prop == null) return;
		var v:Dynamic = prop;
		var value:Float = Render.read(v);
		box.withPost(p -> f(p, value));
		if (Render.isReactive(v)) Graph.renderEffect(() -> (Render.read(v) : Float), (x:Float) -> {
			value = x;
			box.onPost(p -> f(p, x));
		});
	}
}
