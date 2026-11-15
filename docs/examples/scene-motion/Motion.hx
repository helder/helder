// title: Motion in markup
// summary: Structure in markup, motion in code: a ring of boxes each turned by its own onFrame, the ring by one Frame.on, a toggle that stops them (the box then draws nothing until it changes)
// tags: 3d, docs, scene markup
// demo: canvas 640x400
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.Quat;
import helder.scene.view.Frame;
import helder.scene.view.SceneTags.*;
import helder.scene.view.SceneView;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// What moves every frame is written in code, not bound: an element's
// onFrame turns its own node, a component's Frame.on turns its ring. Both
// are owned: unmounted (the toggle), they stop, and the <Scene> draws no
// more frames until something changes (it draws on demand).
class Motion implements Markup {
	static final UP = new Vec3(0, 1, 0);
	static final TILT = new Vec3(1, 0, 0);

	static function main() {
		var spinning = signal(true);
		var world = new World("motion"), eye = world.node("eye");
		eye.position = new Vec3(0, 3, 6);
		eye.lookAt(new Vec3(0, 0, 0));
		var camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 50));
		UiWindow.run(<Surface title="Motion" width={640} height={400}>
			<view direction="row" grow={1}>
				<Scene world={world} camera={camera} grow={1}>
					<directionalLight intensity={2.0} rotation={Quat.axisAngle(TILT, -0.9)}/>
					<Show when={spinning} fallback={<Ring turning={false}/>}>
						<Ring turning={true}/>
					</Show>
				</Scene>
				<view width={160} padding={16} row-gap={8} background="#18181b" color="#fafafa">
					<text font-size={16}>Motion</text>
					<view:button onPress={() -> spinning(on -> !on)} padding="6 10" radius={6} background="#3f3f46">
						<text>{spinning() ? "Stop" : "Spin"}</text>
					</view:button>
				</view>
			</view>
		</Surface>);
	}

	// eight boxes on a ring; turning: each spun by its onFrame, the ring by Frame.on
	static function Ring(props:{turning:Bool}):SceneView {
		var ring = Node.NONE, angle = 0.0;
		if (props.turning) Frame.on(dt -> ring.rotation = Quat.axisAngle(UP, angle += dt * 0.4));
		return <node ref={n -> ring = n.node}>
			{[for (k in 0...8) <Box at={k} turning={props.turning}/>]}
		</node>;
	}

	static function Box(props:{at:Int, turning:Bool}):SceneView {
		var a = props.at * Math.PI / 4, spin = 0.0;
		var color = new Vec4(0.3 + 0.08 * props.at, 0.5, 0.9 - 0.08 * props.at, 1);
		return props.turning ? <mesh shape="box" size={0.5} color={color} position={new Vec3(Math.cos(a) * 2, 0, Math.sin(a) * 2)}
			onFrame={f -> f.node.rotation = Quat.axisAngle(UP, spin += f.dt * 2)}/> : <mesh shape="box" size={0.5} color={color}
			position={new Vec3(Math.cos(a) * 2, 0, Math.sin(a) * 2)}/>;
	}
}
