import { signal } from "helder/view";
import { Clock, Event, Key } from "helder/ui";
import { Court, serve, W, H, PADDLE, BALL, WIN } from "./pong";

const PADDLE_SPEED = 320, AI_SPEED = 230, START_SPEED = 240, MAX_SPEED = 560;

// the whole game in named signals (Game.score, Game.ball, ...): a scenario sets them
export function Game() {
	const start = serve();
	const ball = signal(start.ball);
	const left = signal(start.left);
	const right = signal(start.right);
	const score = signal(start.score);
	const over = signal(false);
	const paused = signal(false);
	const velocity = signal({ x: START_SPEED, y: 120 });
	const keys = signal({ up: false, down: false });

	function launch(toRight: boolean) {
		velocity({ x: toRight ? START_SPEED : -START_SPEED, y: (Math.random() * 2 - 1) * 160 });
	}
	// bounce off a paddle: faster each hit, angle from where it struck
	function hit(v: { x: number; y: number }, paddleTop: number, y: number, dir: number) {
		const speed = Math.min(MAX_SPEED, Math.hypot(v.x, v.y) * 1.06);
		const off = (y + BALL / 2 - (paddleTop + PADDLE / 2)) / (PADDLE / 2 + BALL / 2);
		const angle = Math.max(-1, Math.min(1, off));
		return { x: dir * speed * Math.cos(angle), y: speed * Math.sin(angle) };
	}

	// (the frame's time, not the model: the clock's last tick)
	let last = -1;
	Clock.add(t => {
		const dt = last < 0 ? 0 : Math.min(0.05, t - last);
		last = t;
		if (over() || paused()) return true;
		let v = velocity();
		const k = keys();
		const l = Math.max(0, Math.min(H - PADDLE, left() + ((k.down ? 1 : 0) - (k.up ? 1 : 0)) * PADDLE_SPEED * dt));
		// the right paddle follows the ball, only while it comes its way
		const target = v.x > 0 ? ball().y + BALL / 2 - PADDLE / 2 : H / 2 - PADDLE / 2;
		const gap = target - right();
		const r = Math.max(0, Math.min(H - PADDLE, right() + Math.sign(gap) * Math.min(Math.abs(gap), AI_SPEED * dt)));
		let x = ball().x + v.x * dt, y = ball().y + v.y * dt, s = score();
		if (y < 0) { y = 0; v = { x: v.x, y: Math.abs(v.y) }; }
		if (y > H - BALL) { y = H - BALL; v = { x: v.x, y: -Math.abs(v.y) }; }
		if (v.x < 0 && x < 24 && x > 8 && y > l - BALL && y < l + PADDLE) { x = 24; v = hit(v, l, y, 1); }
		if (v.x > 0 && x > W - 24 - BALL && x < W - 8 && y > r - BALL && y < r + PADDLE) { x = W - 24 - BALL; v = hit(v, r, y, -1); }
		velocity(v);
		if (x < -BALL || x > W) {
			const leftScored = x > W;
			s = leftScored ? [s[0] + 1, s[1]] : [s[0], s[1] + 1];
			x = W / 2 - BALL / 2;
			y = H / 2 - BALL / 2;
			launch(!leftScored);
		}
		ball({ x, y });
		left(l);
		right(r);
		score(s);
		over(Math.max(s[0], s[1]) >= WIN);
		return true;
	});

	function restart() {
		const s = serve();
		ball(s.ball);
		left(s.left);
		right(s.right);
		score(s.score);
		over(false);
		launch(Math.random() < 0.5);
	}

	function key(e: Event, on: boolean) {
		if (e.key === Key.UP || e.key === "w".charCodeAt(0) || e.key === "W".charCodeAt(0)) keys({ ...keys(), up: on });
		if (e.key === Key.DOWN || e.key === "s".charCodeAt(0) || e.key === "S".charCodeAt(0)) keys({ ...keys(), down: on });
		if (on && (e.key === Key.ESCAPE || e.key === "p".charCodeAt(0) || e.key === "P".charCodeAt(0)) && !over()) paused(!paused());
		if (on && e.key === Key.SPACE && over()) restart();
	}
	const state = () => ({ ball: ball(), left: left(), right: right(), score: score(), over: over(), paused: paused() });
	return <view focusable autoFocus onKeyDown={(e: Event) => key(e, true)} onKeyUp={(e: Event) => key(e, false)}>
		<Court state={state}/>
	</view>;
}
