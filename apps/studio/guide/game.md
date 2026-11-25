# Game

A game is a view whose state changes every frame: a step on the clock
(`Clock.add`, called with the time in seconds, kept while it returns
true), signals for what moves, absolutely placed views as its shapes, and
key and pointer events on a focused view.

```tsx file=game.tsx
import { signal } from "helder/view";
import { Clock, Event, Key } from "helder/ui";

const W = 480, H = 320, PADDLE = 80, BALL = 12;

export function Game() {
	const paddle = signal(W / 2 - PADDLE / 2);
	const ball = signal({ x: W / 2, y: H / 2 });
	const score = signal(0);
	let vx = 180, vy = -220, left = false, right = false, last = -1;
	Clock.add(t => {
		const dt = last < 0 ? 0 : Math.min(0.05, t - last);
		last = t;
		if (left) paddle(p => Math.max(0, p - 320 * dt));
		if (right) paddle(p => Math.min(W - PADDLE, p + 320 * dt));
		let { x, y } = ball();
		x += vx * dt;
		y += vy * dt;
		if (x < 0 || x > W - BALL) vx = -vx;
		if (y < 0) vy = -vy;
		const p = paddle();
		if (vy > 0 && y > H - 24 - BALL && y < H - 14 && x > p - BALL && x < p + PADDLE) {
			vy = -vy;
			score(s => s + 1);
		}
		if (y > H) {
			x = W / 2;
			y = H / 2;
			score(0);
		}
		ball({ x: Math.max(0, Math.min(W - BALL, x)), y: y });
		return true;
	});
	function key(e: Event, down: boolean) {
		if (e.key === Key.LEFT || e.key === "a".charCodeAt(0)) left = down;
		if (e.key === Key.RIGHT || e.key === "d".charCodeAt(0)) right = down;
	}
	return <view width={W} height={H} background="#0e1424" focusable autofocus overflow="hidden"
		onKeyDown={(e: Event) => key(e, true)} onKeyUp={(e: Event) => key(e, false)}
		onPointerMove={(e: Event) => paddle(Math.max(0, Math.min(W - PADDLE, e.localX - PADDLE / 2)))}>
		<view position="absolute" left={ball().x} top={ball().y} width={BALL} height={BALL} radius={BALL / 2} background="#f2c65a"/>
		<view position="absolute" left={paddle()} top={H - 24} width={PADDLE} height={10} radius={5} background="#9fd3ff"/>
		<text position="absolute" left={12} top={8} font-size={14} color="#e8e2d0">{`Score ${score()}`}</text>
	</view>;
}
```

```tsx file=game.story.tsx
import { story } from "helder/story";
import { Game } from "./game";

// (play: the story runs 2 s of its clock before a screenshot is taken)
export const play = story({ name: "Game/Play", width: 480, height: 320, render: c => {
	c.play(2);
	return <Game/>;
} });
```

- On the canvas a story runs live; keys reach it when the user plays it
  (Play, or a double click on its frame).
- Timing: the step's `t` is seconds; use the difference (`dt`) so speed
  doesn't depend on the frame rate. Cap it (a paused screen resumes).
- Many objects: one signal holding an array, `For` over it, each a view.
- Randomness that repeats: the story's `c.random()` (its seed's).
