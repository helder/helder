// A <Scene> of TypeScript's markup given helder/gfx's values (the 3d lane:
// tests/lanes/Scene.hx's sceneProps): a red sphere placed by a vec3 right of
// the centre, a box turned by a Quat behind it, a vec4 colour; drawn
// headless, the sphere's spot red and the other side the background. Before
// SceneRenderer took them as Haxe's values, the run threw (a class cast).
import { UiWindow, Surface } from "helder/ui";
import { Scene } from "helder/scene/view";
import { vec3, vec4, Quat } from "helder/gfx";

UiWindow.run(<Surface title="Props" width={320} height={240}>
	<Scene grow={1}>
		<directionalLight intensity={2} rotation={Quat.fromEuler(-0.7, 0.3, 0)}/>
		<mesh position={vec3(1.4, 0, 0)}>
			<sphereGeometry radius={0.8}/>
			<unlitMaterial color={vec4(1, 0, 0, 1)}/>
		</mesh>
		<mesh position={vec3(0, 0, -3)} rotation={Quat.fromEuler(0.4, 0.6, 0)}>
			<boxGeometry width={0.5} height={0.5} depth={0.5}/>
			<standardMaterial color={vec4(0.2, 0.4, 1, 1)}/>
		</mesh>
	</Scene>
</Surface>);
