import { Read, signal } from "helder/view";
import { Clock } from "helder/ui";
import { Scene, Effects, Ssao } from "helder/scene/view";
import { vec3, vec4 } from "helder/gfx";
import { Quat } from "helder/math";
import { Renderer, Shadows } from "helder/scene";
import { pieces as town, QUAY, LIGHTHOUSE } from "./harbour";
import { dressing } from "./dressing";
import { crease, rise, V3 } from "./paper";

const pieces = [...town, ...dressing()];

// seconds since the page was opened (the pop-up's clock)
export const time = signal(0);

// the time of day: a breezy morning, dusk with the lighthouse lit, night
export type Sky = "day" | "dusk" | "night";
export const sky = signal<Sky>("day");

// each time of day's light: page colour, key, fill, hemisphere, how bright
// the lamps glow, and whether the lighthouse beam turns
type Mood = { bg: string; key: V3; keyI: number; fill: V3; fillI: number; skyC: V3; ground: V3; hemiI: number; glow: number; beam: number; exposure: number };
const moods: Record<Sky, Mood> = {
	day: { bg: "#86aab0", key: [1.0, 0.94, 0.85], keyI: 2.6, fill: [1.0, 0.95, 0.9], fillI: 0.75, skyC: [1.0, 0.93, 0.82], ground: [0.62, 0.42, 0.25], hemiI: 0.45, glow: 1, beam: 0, exposure: 1 },
	dusk: { bg: "#6b7f96", key: [1.0, 0.5, 0.3], keyI: 0.8, fill: [0.5, 0.45, 0.85], fillI: 0.25, skyC: [0.6, 0.42, 0.62], ground: [0.25, 0.18, 0.32], hemiI: 0.3, glow: 3, beam: 0.25, exposure: 0.6 },
	night: { bg: "#1f2a40", key: [0.5, 0.6, 0.95], keyI: 0.35, fill: [0.35, 0.42, 0.8], fillI: 0.15, skyC: [0.3, 0.36, 0.65], ground: [0.08, 0.08, 0.18], hemiI: 0.3, glow: 5, beam: 0.2, exposure: 0.5 },
};

// the lantern's height on the page and the beam's turn (radians a second)
const LANTERN_Y = QUAY + 5.65;
const SWEEP = 0.9;
const BEAM = 13;

// the engine's own soft shadows, opted in: crisp where a card meets the
// page, widening with the gap (penumbra ~0.25 x gap)
function softShadows(r: Renderer) {
	const s = new Shadows(r.device, 2048).soft(0.22, 16, 0.12);
	s.bias = 0.001;
	r.use(s);
}

const v = (a: V3) => vec3(a[0], a[1], a[2]);
const q = (a: V3) => Quat.fromEuler(a[0], a[1], a[2]);

// the harbour diorama at a moment of its rise (t: seconds since opening)
export function Diorama(p: { t: Read<number>; sky?: Read<Sky> }) {
	const m = () => moods[p.sky ? p.sky() : "day"];
	const glow = () => m().glow; // lamps and the lantern burn brighter as it darkens
	// the beam only shines once the lighthouse stands
	const up = () => Math.min(1, Math.max(0, rise(p.t(), LIGHTHOUSE.delay)));
	return <view flexGrow={1} background={m().bg}>
		<Scene flexGrow={1} setup={softShadows}>
			<camera position={vec3(-0.6, 21, 15.2)} rotation={Quat.fromEuler(-0.86, 0, 0)} fov={0.5} near={1} far={90}/>
			<directionalLight color={v(m().key)} intensity={m().keyI} rotation={Quat.fromEuler(-0.9, -0.95, 0)} castShadows={true} shadowSize={2048} shadowRadius={2}/>
			<directionalLight color={v(m().fill)} intensity={m().fillI} rotation={Quat.fromEuler(-0.6, 0, 0)} castShadows={false}/>
			<hemisphereLight sky={v(m().skyC)} ground={v(m().ground)} intensity={m().hemiI}/>
			{/* the lighthouse beam: a pale cone of light from the lantern, turning */}
			{m().beam > 0 ? <node position={vec3(LIGHTHOUSE.x, LANTERN_Y, LIGHTHOUSE.z)} rotation={Quat.fromEuler(0, p.t() * SWEEP, 0)} scale={vec3(up(), up(), up())}>
				<mesh position={vec3(BEAM / 2, -0.35, 0)} rotation={Quat.fromEuler(0, 0, Math.PI / 2 + 0.05)}>
					<coneGeometry radius={1.6} height={BEAM} radialSegments={24}/>
					<unlitMaterial color={vec4(1.0, 0.92, 0.6, m().beam * up())} blend="alpha" doubleSided={true} castShadows={false}/>
				</mesh>
				<pointLight position={vec3(4.5, -2.5, 0)} color={vec3(1.0, 0.88, 0.55)} intensity={m().beam * 30 * up()} range={7}/>
			</node> : null}
			{pieces.map(pc => <node position={vec3(pc.x, pc.y, pc.z)} rotation={Quat.fromEuler(0, pc.ry, 0)}>
				<node position={vec3(0, 0, pc.front)} rotation={Quat.fromEuler(crease(p.t(), pc.delay), 0, 0)}>
				<node position={vec3(0, 0, -pc.front)}>
					{pc.groups.map(g => <node position={g.anim ? v(g.anim(p.t())[0]) : v(g.p)} rotation={g.anim ? q(g.anim(p.t())[1]) : q(g.r)} scale={g.anim ? v(g.anim(p.t())[2]) : v(g.s)}>
						{g.prims.map(m => m.k === "box" ?
							<mesh position={v(m.p)} rotation={q(m.r)} scale={v(m.s)}>
								<boxGeometry width={m.w} height={m.h} depth={m.d}/>
								<lambertMaterial color={m.c}/>
							</mesh> : m.k === "torus" ?
							<mesh position={v(m.p)} rotation={q(m.r)} scale={v(m.s)}>
								<torusGeometry radius={m.rb} tube={m.d} radialSegments={10} tubularSegments={28}/>
								<lambertMaterial color={m.c}/>
							</mesh> : m.k === "cone" ?
							<mesh position={v(m.p)} rotation={q(m.r)} scale={v(m.s)}>
								<coneGeometry radius={m.rb} height={m.h} radialSegments={m.seg | 0}/>
								<lambertMaterial color={m.c}/>
							</mesh> :
							<mesh position={v(m.p)} rotation={q(m.r)} scale={v(m.s)}>
								<cylinderGeometry radiusTop={m.rt} radiusBottom={m.rb} height={m.h} radialSegments={m.seg | 0} thetaStart={m.ts} thetaLength={m.th}/>
								<lambertMaterial color={m.c} emissive={vec3(m.glow * glow(), m.glow * 0.75 * glow(), m.glow * 0.2 * glow())}/>
							</mesh>)}
					</node>)}
				</node>
				</node>
			</node>)}
			<Effects exposure={m().exposure}>
				<Ssao radius={0.6} intensity={0.8}/>
			</Effects>
		</Scene>
	</view>;
}

// the app: the page opens and the town folds up; a press folds it again
export function App() {
	Clock.add(dt => {
		time(time() + Math.min(Math.max(dt, 0), 0.05));
		return true;
	});
	return <view flexGrow={1} onPointerDown={() => time(0)}>
		<Diorama t={time} sky={sky}/>
	</view>;
}
