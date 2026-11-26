# Game

A game here is two things:

- **Stills on the canvas.** Each screen is a scenario: the real game at
  one moment, its model set by `boot`, its clock standing: exact and the
  same every time. Name them for the moment: "Pong/Serve", "Pong/Rally",
  "Pong/Point scored", "Pong/Game over".
- **The game itself runs in Play.** The app (`main.tsx`) runs the clock and
  takes the keys; the user plays it in a window of its own (Play, or a
  double click on a frame), rebuilt as you change it.

## Build it a step at a time

The user watches the canvas grow with the work, so let it:

1. First something that draws: the court and the paddles as still shapes,
   the model in exported signals, and a scenario of it. `build.check`, and
   see it on the canvas (`run.snap`).
2. Then one concept per step: the ball and its motion, the keys, scoring,
   game over. Each a small `project.patch`, then `build.check`, and the
   screen updates. Add a moment's scenario when the moment exists (a
   point scored, once there is scoring).

Keep each step real, no throwaway scaffolding, and build once per
concept, not after every line.

## The model, drawn

```tsx file=pong.tsx
import { Read, Show } from "helder/view";

export const W = 480, H = 320, PADDLE = 64, BALL = 10;

export type State = { ball: { x: number; y: number }; left: number; right: number; score: number[]; over: boolean };

export function serve(): State {
	return { ball: { x: W / 2 - BALL / 2, y: H / 2 - BALL / 2 }, left: H / 2 - PADDLE / 2, right: H / 2 - PADDLE / 2, score: [0, 0], over: false };
}

// the court as a state draws it
export function Court(props: { state: Read<State> }) {
	return <view width={W} height={H} background="#0e1424" overflow="hidden">
		<view position="absolute" left={W / 2 - 1} top={0} width={2} height={H} background="#26304a"/>
		<view position="absolute" left={16} top={props.state().left} width={8} height={PADDLE} borderRadius={4} background="#9fd3ff"/>
		<view position="absolute" left={W - 24} top={props.state().right} width={8} height={PADDLE} borderRadius={4} background="#f2c65a"/>
		<view position="absolute" left={props.state().ball.x} top={props.state().ball.y} width={BALL} height={BALL} borderRadius={BALL / 2} background="#e8e2d0"/>
		<view position="absolute" left={0} right={0} top={12} alignItems="center">
			<text fontSize={24} fontWeight={700} color="#e8e2d0">{`${props.state().score[0]}   ${props.state().score[1]}`}</text>
		</view>
		<Show when={() => props.state().over}>
			<view position="absolute" left={0} right={0} top={H / 2 - 20} alignItems="center">
				<text fontSize={28} fontWeight={700} color="#f2c65a">Game over</text>
			</view>
		</Show>
	</view>;
}
```

## The game: its model in top-level signals

```tsx file=game.tsx
import { signal } from "helder/view";
import { Clock, Event, Key } from "helder/ui";
import { Court, serve, W, H, PADDLE, BALL } from "./pong";

// the model: a scenario's boot sets these
export const state = signal(serve());
export const velocity = signal({ x: 200, y: 140 });
export const keys = signal({ up: false, down: false });

export function Game() {
	// (the frame's time, not the model)
	let last = -1;
	Clock.add(t => {
		const dt = last < 0 ? 0 : Math.min(0.05, t - last);
		last = t;
		const s = state(), k = keys();
		let v = velocity();
		if (s.over) return true;
		const left = Math.max(0, Math.min(H - PADDLE, s.left + ((k.down ? 1 : 0) - (k.up ? 1 : 0)) * 300 * dt));
		// (the right paddle follows the ball)
		const right = Math.max(0, Math.min(H - PADDLE, s.right + Math.sign(s.ball.y - s.right - PADDLE / 2) * 200 * dt));
		let x = s.ball.x + v.x * dt, y = s.ball.y + v.y * dt, score = s.score;
		if (y < 0 || y > H - BALL) v = { x: v.x, y: -v.y };
		if (v.x < 0 && x < 24 && y > left - BALL && y < left + PADDLE) v = { x: -v.x, y: v.y };
		if (v.x > 0 && x > W - 24 - BALL && y > right - BALL && y < right + PADDLE) v = { x: -v.x, y: v.y };
		if (x < -BALL || x > W) {
			score = x < 0 ? [score[0], score[1] + 1] : [score[0] + 1, score[1]];
			x = W / 2;
			y = H / 2;
		}
		velocity(v);
		state({ ball: { x: x, y: Math.max(0, Math.min(H - BALL, y)) }, left: left, right: right, score: score, over: Math.max(score[0], score[1]) >= 7 });
		return true;
	});
	function key(e: Event, on: boolean) {
		if (e.key === Key.UP || e.key === "w".charCodeAt(0)) keys({ ...keys(), up: on });
		if (e.key === Key.DOWN || e.key === "s".charCodeAt(0)) keys({ ...keys(), down: on });
		if (on && e.key === Key.SPACE && state().over) state(serve());
	}
	return <view focusable autoFocus onKeyDown={(e: Event) => key(e, true)} onKeyUp={(e: Event) => key(e, false)}>
		<Court state={state}/>
	</view>;
}
```

```tsx file=main.tsx
import { UiWindow, Surface } from "helder/ui";
import { Game } from "./game";
import { W, H } from "./pong";

UiWindow.run(
	<Surface title="Pong" width={W} height={H}>
		<Game/>
	</Surface>
);
```

## The moments, as scenarios

```tsx file=pong.scenario.tsx
import { scenario } from "helder/scenario";
import { state } from "./game";
import { serve, W } from "./pong";

export const serving = scenario({ name: "Pong/Serve" });
export const rally = scenario({ name: "Pong/Rally", boot() { state({ ...serve(), ball: { x: 300, y: 118 }, left: 92, right: 150, score: [3, 2] }); } });
export const point = scenario({ name: "Pong/Point scored", boot() { state({ ...serve(), ball: { x: W - 6, y: 200 }, score: [4, 2] }); } });
export const over = scenario({ name: "Pong/Game over", boot() { state({ ...serve(), score: [7, 5], over: true }); } });
// (loop: where motion is the point; 2 s from its moment, played while hovered)
export const moving = scenario({ name: "Pong/In motion", loop: 2 });
```

- The step's `t` is seconds: move by `dt`, so speed doesn't depend on the
  frame rate; cap it. A still's clock stands: its model stays as boot set it.
- Keys reach a focused view (`focusable autofocus`): in Play's window.
- Pointer: `onPointerMove` (`e.localX`, `e.localY`) on the view.
- Many objects: one signal holding an array, `For` over it.
- A 3D game: the same, its scene in markup (`studio.guide {topic: "3d"}`).
