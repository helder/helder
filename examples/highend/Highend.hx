// title: High-end effects
// summary: Screen-space reflections on a polished floor, god rays from a low sun, TAA or SMAA, motion blur as the camera turns, and a transform gizmo on what you click
// tags: 3d, post, gizmo, scene markup
// demo: canvas 760x440
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.render.Light;
import helder.scene.render.Sky;
import helder.scene.math.Quat;
import helder.scene.view.EffectTags.*;
import helder.scene.view.SceneTags.*;
import helder.scene.view.SceneView;
import helder.scene.view.TransformGizmo.GizmoMode;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// helder.scene's high end (src/helder/scene/README.md, "Post effects"), in
// markup:
//
// - <Ssr>        screen-space reflections: the polished floor and the
//                mirror reflect what is on the screen, by Fresnel
// - <GodRays>    the low sun's light streaming past the pillars
// - <Taa>        temporal antialiasing (the frame jittered, gathered with
//                its history); or <Smaa>, or <Fxaa>
// - <MotionBlur> the camera's motion blur: drag to orbit and see it
// - <TransformGizmo> on the shape clicked: drag an arrow to move it, a
//                ring to turn it, an arm to scale it (the mode's buttons);
//                a drag elsewhere orbits (the two share the box's pointers)
//
// Only the effects this file names are linked into it.
class Highend implements Markup {
	static function main() {
		var ssr = signal(true), rays = signal(true), blur = signal(true), aa = signal("taa");
		var picked = signal("sphere"), mode = signal(Translate);
		var world = new World("highend"), eye = world.node("eye");
		var camera = Camera.attach(eye, Camera.perspective(0.85, 0.1, 80));
		eye.position = new Vec3(0.3, 1.8, 6.5);
		eye.lookAt(new Vec3(0, 1.2, -2));
		// (a low sun before the camera, made in code: what the god rays stream from)
		var sun = world.node("sun");
		sun.lookAt(new Vec3(-0.15, -0.3, 1));
		Light.attach(sun, Light.directional(new Vec3(1, 0.85, 0.65), 1.4));
		UiWindow.run(<Surface title="High-end effects" width={760} height={440}>
			<view direction="row" grow={1}>
				<Scene world={world} camera={camera} grow={1} setup={r -> {
					var sky = new Sky(r.device);
					sky.zenith = new Vec3(0.05, 0.08, 0.18);
					sky.horizon = new Vec3(0.9, 0.6, 0.4);
					sky.sunColor = new Vec3(5, 3.6, 2);
					r.use(sky);
				}}>
					<Effects bloom={0.04} toneMap={AgX}>
						<Show when={ssr()}><Ssr maxDistance={10.0} thickness={0.3} steps={64}/></Show>
						<Show when={rays()}><GodRays intensity={0.45}/></Show>
						<Show when={blur()}><MotionBlur strength={0.6}/></Show>
						<Show when={aa() == "taa"}><Taa/></Show>
						<Show when={aa() == "smaa"}><Smaa/></Show>
						<Show when={aa() == "fxaa"}><Fxaa/></Show>
					</Effects>
					<OrbitControls target={new Vec3(0, 0.8, 0)} minDistance={3.0} maxDistance={20.0}/>
					<mesh shape="plane" size={60.0} color={new Vec4(0.08, 0.08, 0.09, 1)} metallic={0.2} roughness={0.08}/>
					<mesh shape="box" position={new Vec3(2.3, 0.85, -1.4)} rotation={Quat.axisAngle(new Vec3(0, 1, 0), -0.6)} scale={new Vec3(1.6, 1.6, 0.06)}
						color={new Vec4(0.95, 0.95, 0.95, 1)} metallic={1.0} roughness={0.02}/>
					<Shape name="box" shape="box" at={new Vec3(-1.8, 0.5, -0.4)} size={1.0} color={new Vec4(0.85, 0.3, 0.2, 1)} picked={picked}/>
					<Shape name="sphere" shape="sphere" at={new Vec3(0, 0.6, 0.4)} size={1.2} color={new Vec4(0.9, 0.88, 0.82, 1)} picked={picked}/>
					<Shape name="cube" shape="box" at={new Vec3(0.9, 0.3, 1.0)} size={0.6} color={new Vec4(0.25, 0.45, 0.9, 1)} picked={picked}/>
					<Pillar x={-4.0}/>
					<Pillar x={-2.4}/>
					<Pillar x={-0.8}/>
					<Pillar x={0.8}/>
					<Pillar x={2.4}/>
					<Pillar x={4.0}/>
					<TransformGizmo of={world.root.find(picked())} mode={mode} snap={0.1}/>
					<mesh shape="box" position={new Vec3(0, 5.2, -6)} scale={new Vec3(10, 0.5, 0.6)} color={new Vec4(0.35, 0.3, 0.28, 1)}/>
				</Scene>
				<view width={190} padding={14} row-gap={6} background="#18181b" color="#fafafa" font-size={13}>
					<text font-size={15}>High-end effects</text>
					<Toggle label="Reflections (SSR)" on={() -> ssr()} flip={() -> ssr(!ssr())}/>
					<Toggle label="God rays" on={() -> rays()} flip={() -> rays(!rays())}/>
					<Toggle label="Motion blur" on={() -> blur()} flip={() -> blur(!blur())}/>
					<Toggle label="TAA" on={() -> aa() == "taa"} flip={() -> aa(aa() == "taa" ? "none" : "taa")}/>
					<Toggle label="SMAA" on={() -> aa() == "smaa"} flip={() -> aa(aa() == "smaa" ? "none" : "smaa")}/>
					<Toggle label="FXAA" on={() -> aa() == "fxaa"} flip={() -> aa(aa() == "fxaa" ? "none" : "fxaa")}/>
					<text color="#a1a1aa">Gizmo on: {picked} (click a shape)</text>
					<Toggle label="Move" on={() -> mode() == Translate} flip={() -> mode(Translate)}/>
					<Toggle label="Turn" on={() -> mode() == Rotate} flip={() -> mode(Rotate)}/>
					<Toggle label="Scale" on={() -> mode() == Scale} flip={() -> mode(Scale)}/>
				</view>
			</view>
		</Surface>);
	}

	// a shape a click picks: the gizmo goes to it
	static function Shape(props:{name:String, shape:String, at:Vec3, size:Float, color:Vec4, picked:Signal<String>}):SceneView
		return <mesh name={props.name} shape={props.shape} size={props.size} position={props.at} color={props.color} roughness={0.4}
			onClick={_ -> props.picked(props.name)}/>;

	// a pillar of the colonnade before the sun
	static function Pillar(props:{x:Float}):SceneView
		return <mesh shape="box" position={new Vec3(props.x, 2.5, -6)} scale={new Vec3(0.5, 5, 0.5)} color={new Vec4(0.35, 0.3, 0.28, 1)}/>;

	// a switch in the panel: a dot lit while on, flipped by a press
	static function Toggle(props:{label:String, on:Void->Bool, flip:Void->Void}):View
		return <view role="switch" direction="row" column-gap={8} align-items="center" padding="4 6" radius={4} background="#27272a" onPress={props.flip}>
			<view width={12} height={12} radius={6} background={props.on() ? "#facc15" : "#52525b"}/>
			<text>{props.label}</text>
		</view>;
}
