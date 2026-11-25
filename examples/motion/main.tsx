// title: Motion in TypeScript
// summary: Motion as property tracks from TSX: rows coming and going, a matched zoom, a theme switch, reduced motion
// tags: typescript, ui, view, motion
// demo: canvas 760x520
// examples/motion/Motion.hx in TypeScript: the same attributes (motion,
// transition, matched, lead and trail, ride), declared on the nodes; the
// list moves its rows edge by edge as they come and go, a tile pressed
// flies into the stage and back, the theme's colours move through OKLab,
// Clock.reducedMotion snaps travel and keeps a short fade.
import { signal, For, Show } from "helder/view";
import { UiWindow, Surface, Clock } from "helder/ui";

const rows = signal([1, 2, 3, 4]);
let next = 5;
const dark = signal(false);
const reduced = signal(false);
const zoomed = signal(-1);
const TILES = ["#f97316", "#22c55e", "#3b82f6", "#a855f7"];

function add() {
	rows(rows().concat([next++]));
}

function removeOne() {
	const r = rows();
	if (r.length > 0) rows(r.filter(x => x !== r[r.length > 2 ? 1 : 0]));
}

function shuffle() {
	const r = rows().slice().reverse();
	rows(r.length > 2 ? r.slice(1).concat([r[0]]) : r);
}

function setReduced(on: boolean) {
	reduced(on);
	Clock.reducedMotion = on;
}

function Button(props: { tag: string; label: () => string; onPress: () => void }) {
	return <button tag={props.tag} cursor="pointer" padding="6 12" borderRadius={8}
		background={dark() ? "#27272a" : "#ffffff"} color={dark() ? "#fafafa" : "#18181b"} borderWidth={1} borderColor={dark() ? "#3f3f46" : "#e4e4e7"}
		onPress={() => props.onPress()}>{props.label()}</button>;
}

function Tile(props: { i: number; big: boolean }) {
	return <view tag={"tile-" + props.i} matched={"tile-" + props.i} flexGrow={1} borderRadius={props.big ? 28 : 16} background={TILES[props.i]} padding={16}
		cursor="pointer" justifyContent="end" onPress={() => zoomed(props.big ? -1 : props.i)}>
		<text color="#ffffff" fontSize={props.big ? 28 : 16} fontWeight={700}>{"Tile " + (props.i + 1)}</text>
	</view>;
}

function App() {
	return <view flexGrow={1} padding={20} rowGap={16} fontSize={14} motion="default" motionColor="calm"
		background={dark() ? "#09090b" : "#f4f4f5"} color={dark() ? "#fafafa" : "#18181b"}>
		<view flexDirection="row" columnGap={8} alignItems="center">
			<text fontSize={22} fontWeight={700} flexGrow={1}>Motion</text>
			<Button tag="add" label={() => "Add"} onPress={add}/>
			<Button tag="remove" label={() => "Remove"} onPress={removeOne}/>
			<Button tag="shuffle" label={() => "Shuffle"} onPress={shuffle}/>
			<Button tag="theme" label={() => dark() ? "Light" : "Dark"} onPress={() => dark(d => !d)}/>
			<Button tag="reduce" label={() => reduced() ? "Full motion" : "Reduced motion"} onPress={() => setReduced(!reduced())}/>
		</view>
		<view flexDirection="row" columnGap={16} flexGrow={1} minHeight={0}>
			<view tag="list" width={260} rowGap={8} padding={12} borderRadius={14} alignItems="stretch" lead="snappy" trail="calm"
				background={dark() ? "#18181b" : "#ffffff"}>
				<For each={rows}>{n => <view tag={"row-" + n()} transition="fade slide-up" flexDirection="row" alignItems="center"
					columnGap={10} padding="10 12" borderRadius={10} background={dark() ? "#27272a" : "#f4f4f5"}>
					<view width={10} height={10} borderRadius={5} background={TILES[n() % 4]}/>
					<text flexGrow={1}>{"Row " + n()}</text>
					<text ride="trailing" color={dark() ? "#a1a1aa" : "#71717a"}>{"#" + n()}</text>
				</view>}</For>
			</view>
			<view tag="stage" flexGrow={1} borderRadius={20}>
				<Show when={() => zoomed() < 0} fallback={<view tag="zoom" flexGrow={1}>{() => <Tile i={zoomed()} big={true}/>}</view>}>
					<view tag="grid" flexGrow={1} rowGap={12} transition="fade scale">
						<view flexDirection="row" flexGrow={1} columnGap={12}><Tile i={0} big={false}/><Tile i={1} big={false}/></view>
						<view flexDirection="row" flexGrow={1} columnGap={12}><Tile i={2} big={false}/><Tile i={3} big={false}/></view>
					</view>
				</Show>
			</view>
		</view>
	</view>;
}

UiWindow.run(
	<Surface title="Motion" width={760} height={520}>
		<App/>
	</Surface>
);
