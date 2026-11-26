// title: Post effects
// summary: A <Scene>'s post effects in markup, each toggled: ambient occlusion, depth of field (a lens or tilt-shift), outlines around what you click, FXAA, a colour grade
// tags: 3d, post, scene markup
// demo: canvas 760x440
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.Camera;
import helder.scene.World;
import helder.scene.render.Light;
import helder.math.Quat;
import helder.scene.view.EffectTags.*;
import helder.scene.view.SceneTags.*;
import helder.scene.view.SceneView;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// helder.scene's post effects (src/helder/scene/README.md, "Post effects"),
// all markup:
//
// - <Effects> configures the <Scene>'s post chain (and makes the box HDR):
//   bloom, the tone map, the vignette.
// - Each effect inside it is set on the chain while its tag is there, so
//   a <Show> toggles it: when the tag goes, the effect is unset.
//     <Ssao>     ambient occlusion (GTAO): corners and contacts darken,
//                the sun's light does not
//     <Dof>      depth of field: a lens focused at a distance, or with
//                tiltShift a diorama's band, by depth (the far island is
//                blurred though it sits in the band on the screen)
//     <Outline>  edges around the selection: each shape's outline prop is
//                its selection group (1 while picked, 0 not), as data
//     <Fxaa>     antialiasing in the composite
//     <Lut>      a colour grade, here a function made into a 16-cubed table
// - The camera orbits (drag, pinch, wheel: <OrbitControls>).
//
// Only the effects this file names are linked into it.
class Postfx implements Markup {
	static function main() {
		// (each switch, the lens: "none", "focus" or "tilt", and the shape picked)
		var ao = signal(true), lens = signal("tilt"), outline = signal(true), fxaa = signal(true), lut = signal(false), bloom = signal(true);
		var picked = signal("sphere");
		var world = new World("postfx"), eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 80));
		eye.position = new Vec3(0.2, 1.7, 6.2);
		eye.lookAt(new Vec3(0, 0.8, 0));
		// (the sun, made in code: turned down towards the courtyard)
		var sun = world.node("sun");
		sun.rotation = Quat.fromEuler(-0.9, 0.6, 0);
		Light.attach(sun, Light.directional(new Vec3(1, 0.96, 0.9), 1.6));
		UiWindow.run(<Surface title="Post effects" width={760} height={440}>
			<view flexDirection="row" flexGrow={1}>
				<Scene world={world} camera={camera} flexGrow={1}>
					<Effects bloom={bloom() ? 0.05 : 0.0} toneMap={AgX} vignette={0.2}>
						<Show when={ao()}><Ssao radius={0.6} intensity={1.4} samples={6}/></Show>
						<Show when={lens() == "focus"}><Dof distance={6.5} aperture={0.03}/></Show>
						<Show when={lens() == "tilt"}><Dof tiltShift={true} band={0.15} falloff={0.35} strength={1.0}/></Show>
						<Show when={outline()}><Outline width={2.0} color={new Vec4(1, 0.78, 0.15, 1)}/></Show>
						<Show when={fxaa()}><Fxaa/></Show>
						<Show when={lut()}><Lut grade={grade}/></Show>
					</Effects>
					<OrbitControls target={new Vec3(0, 0.8, 0)} minDistance={3.0} maxDistance={20.0}/>
					<mesh shape="plane" size={60.0} color={new Vec4(0.6, 0.6, 0.58, 1)}/>
					<mesh shape="box" position={new Vec3(0, 1.5, -2.6)} scale={new Vec3(9, 3, 0.4)} color={new Vec4(0.72, 0.68, 0.62, 1)}/>
					<Shape name="box" shape="box" at={new Vec3(-1.9, 0.5, -0.6)} size={1.0} color={new Vec4(0.85, 0.45, 0.3, 1)} picked={picked}/>
					<Shape name="sphere" shape="sphere" at={new Vec3(-0.1, 0.6, 0.2)} size={1.2} color={new Vec4(0.9, 0.85, 0.8, 1)} picked={picked}/>
					<Shape name="pillar" shape="box" at={new Vec3(1.3, 1.3, -0.9)} size={1.0} scale={new Vec3(0.45, 2.6, 0.45)} color={new Vec4(0.72, 0.68, 0.62, 1)}
						picked={picked}/>
					<Shape name="cube" shape="box" at={new Vec3(2.4, 0.25, -1.4)} size={0.5} color={new Vec4(0.35, 0.6, 0.35, 1)} picked={picked}/>
					<mesh shape="sphere" size={2.2} position={new Vec3(-3.2, 1.1, -18)} color={new Vec4(0.35, 0.6, 0.35, 1)}/>
				</Scene>
				<view width={190} padding={14} rowGap={6} background="#18181b" color="#fafafa" fontSize={13}>
					<text fontSize={15}>Post effects</text>
					<Toggle label="Ambient occlusion" on={() -> ao()} flip={() -> ao(!ao())}/>
					<Toggle label="Lens: focus" on={() -> lens() == "focus"} flip={() -> lens(lens() == "focus" ? "none" : "focus")}/>
					<Toggle label="Lens: tilt-shift" on={() -> lens() == "tilt"} flip={() -> lens(lens() == "tilt" ? "none" : "tilt")}/>
					<Toggle label="Outline" on={() -> outline()} flip={() -> outline(!outline())}/>
					<Toggle label="FXAA" on={() -> fxaa()} flip={() -> fxaa(!fxaa())}/>
					<Toggle label="Colour grade (LUT)" on={() -> lut()} flip={() -> lut(!lut())}/>
					<Toggle label="Bloom" on={() -> bloom()} flip={() -> bloom(!bloom())}/>
					<text color="#a1a1aa">Selected: {picked} (click a shape)</text>
				</view>
			</view>
		</Surface>);
	}

	// a shape a click selects: its outline group 1 while it is the one picked
	static function Shape(props:{name:String, shape:String, at:Vec3, size:Float, ?scale:Vec3, color:Vec4, picked:Signal<String>}):SceneView
		return <mesh shape={props.shape} size={props.size} position={props.at} scale={props.scale ?? new Vec3(1, 1, 1)} color={props.color}
			outline={props.picked() == props.name ? 1 : 0} onClick={_ -> props.picked(props.name)}/>;

	// a switch in the panel: a dot lit while on, flipped by a press
	static function Toggle(props:{label:String, on:Void->Bool, flip:Void->Void}):View
		return <view role="switch" flexDirection="row" columnGap={8} alignItems="center" padding="4 6" borderRadius={4} background="#27272a" onPress={props.flip}>
			<view width={12} height={12} borderRadius={6} background={props.on() ? "#facc15" : "#52525b"}/>
			<text>{props.label}</text>
		</view>;

	// a colour grade (display values in and out): teal shadows, warm
	// highlights, a little more saturation
	static function grade(r:Float, g:Float, b:Float):Vec3 {
		var y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
		var t = y * y * (3 - 2 * y), k = 1.25;
		return new Vec3(y + (r - y) * k - (1 - t) * 0.03 + t * 0.06, y + (g - y) * k + 0.02, y + (b - y) * k + (1 - t) * 0.06 - t * 0.05);
	}
}
