// The harbour's dressing and life: what a working quay would hold, in
// tight groups of different pieces (law 8), and its own life (law 12):
// gulls gliding, bobbing buoys. Every piece rises on its crease.
import { Piece, Piece3, CARD, LAYER, rnd } from "./paper";
import { QUAY, delayAt } from "./harbour";

const INK = "#3a2a22";
const CREAM = "#f1e6cc";
const WOOD = "#8a5a34", WOOD_D = "#5e3a20", WOOD_L = "#c49a62";
const RED = "#c2553a", NAVY = "#2f4a63", OCHRE = "#dca443";

// a little seeded lateness so neighbours don't rise as one
const late = (z: number, seed: number) => delayAt(z) + rnd(seed) * 0.12;

function bollard(x: number, z: number, y = QUAY): Piece {
	const b = new Piece3();
	b.cyl(0.13, 0.15, 0.38, INK, 0, 0.19, 0, 16);
	b.cyl(0.2, 0.2, 0.07, "#4a3a30", 0, 0.41, 0, 16);
	b.box(0.27, 0.06, LAYER, CREAM, 0, 0.3, 0.15);
	b.front = 0.21;
	return b.done(x, z, late(z, x * 7 + z), 0, y);
}

// two or three barrels with hoops and a lid
function barrels(x: number, z: number, n: number, seed: number): Piece {
	const b = new Piece3();
	for (let i = 0; i < n; i++) {
		const bx = (i - (n - 1) / 2) * 0.48, bz = (i % 2) * -0.3, h = 0.5 + rnd(seed + i) * 0.1;
		b.cyl(0.22, 0.2, h, i === 1 ? "#6f8b5e" : WOOD, bx, h / 2, bz, 18);
		b.cyl(0.235, 0.225, 0.05, INK, bx, h * 0.25, bz, 18);
		b.cyl(0.235, 0.225, 0.05, INK, bx, h * 0.75, bz, 18);
		b.cyl(0.19, 0.19, 0.02, WOOD_L, bx, h + 0.01, bz, 18);
	}
	b.front = 0.26;
	return b.done(x, z, late(z, seed), 0.2, QUAY);
}

// a stack of slatted crates, a fish crate on top
function crates(x: number, z: number, seed: number, ry: number): Piece {
	const b = new Piece3();
	const crate = (cx: number, cy: number, c: string, slat: string) => {
		b.box(0.56, 0.38, 0.42, c, cx, cy + 0.19, 0);
		for (const sy of [0.08, 0.19, 0.3]) b.box(0.56, 0.04, LAYER, slat, cx, cy + sy, 0.21 + LAYER / 2);
		b.box(0.06, 0.38, LAYER, slat, cx - 0.25, cy + 0.19, 0.21 + LAYER);
		b.box(0.06, 0.38, LAYER, slat, cx + 0.25, cy + 0.19, 0.21 + LAYER);
	};
	crate(-0.3, 0, WOOD_L, WOOD);
	crate(0.3, 0, WOOD_L, WOOD);
	crate(0, 0.38, "#3f6c8a", "#2c4d63");
	// a printed fish on the fish crate
	b.disc(0.08, CREAM, -0.04, 0.57, 0.21 + LAYER * 3, LAYER);
	b.box(0.16, 0.1, LAYER, CREAM, 0.06, 0.57, 0.21 + LAYER * 3);
	b.tri(0.14, 0.1, LAYER, CREAM, 0.17, 0.57, 0.21 + LAYER * 3).r = [-Math.PI / 2, 0, 0];
	b.front = 0.26;
	return b.done(x, z, late(z, seed), ry, QUAY);
}

// a harbour lamp: post, arm, glowing lantern, cap
function lamp(x: number, z: number): Piece {
	const b = new Piece3();
	b.box(0.26, 0.3, 0.26, INK, 0, 0.15, 0);
	b.box(0.09, 2.1, 0.09, INK, 0, 1.2, 0);
	b.box(0.3, 0.06, 0.3, INK, 0, 2.25, 0);
	const glass = b.box(0.22, 0.32, 0.22, "#f6d77a", 0, 2.44, 0);
	glass.glow = 0.3;
	b.box(0.04, 0.32, 0.24, INK, 0, 2.44, 0);
	b.cone(0.22, 0.2, INK, 0, 2.7, 0, 4);
	b.disc(0.05, INK, 0, 2.84, 0);
	b.front = 0.16;
	return b.done(x, z, late(z, x), 0.78, QUAY);
}

// a tree: two printed crowns slotted at right angles on a trunk (law 1)
function tree(x: number, z: number, seed: number, scale: number): Piece {
	const b = new Piece3();
	const R = 0.8 * scale, cy = 1.0 * scale + R;
	b.box(0.16, cy, 0.16, WOOD_D, 0, cy / 2, 0);
	for (const turn of [0, Math.PI / 2]) {
		b.group([0, 0, 0], [0, turn, 0]);
		b.disc(R, "#6d8c57", 0, cy, 0, CARD);
		b.disc(R * 0.72, "#7f9d63", 0, cy + R * 0.12, 0, CARD + LAYER * 2);
		for (let i = 0; i < 9; i++) {
			const a = rnd(seed * 31 + i) * Math.PI * 2, d = Math.sqrt(rnd(seed * 17 + i)) * R * 0.7;
			const lx = Math.cos(a) * d, ly = cy + Math.sin(a) * d;
			const c = i % 3 === 0 ? "#557447" : i % 3 === 1 ? "#9cb873" : "#d8624a";
			const r = i % 3 === 2 ? 0.07 : 0.17;
			b.disc(r, c, lx, ly, 0, CARD + LAYER * 4);
		}
	}
	b.front = R + 0.1;
	return b.done(x, z, late(z, seed), 0.45, QUAY);
}

// the headland behind the town: nested layered flats, stepped in value
function hills(): Piece[] {
	const out: Piece[] = [];
	const rows = [
		{ z: -13.5, x: -3, r: 7.5, sx: 1.9, c: "#9fb284", lip: "#b7c79a" },
		{ z: -12.2, x: 6, r: 6.0, sx: 1.7, c: "#8aa070", lip: "#a3b787" },
		{ z: -11.0, x: -8, r: 5.0, sx: 1.6, c: "#7a915f", lip: "#93a876" },
		{ z: -10.0, x: 2, r: 3.6, sx: 2.2, c: "#6d8456", lip: "#869c6b" },
	];
	rows.forEach((h, i) => {
		const b = new Piece3();
		b.group([0, 0, 0], [0, 0, 0], [h.sx, 1, 1]);
		b.disc(h.r, h.c, 0, 0, 0, CARD, true);
		b.disc(h.r * 0.96, h.lip, 0, 0, CARD / 2 + LAYER, LAYER, true);
		b.disc(h.r * 0.9, h.c, 0, -0.06, CARD / 2 + LAYER * 2, LAYER, true);
		// a few printed bushes along the crest
		for (let k = 0; k < 6; k++) {
			const a = 0.5 + rnd(i * 13 + k) * 2.1;
			b.disc(0.32 + rnd(i * 7 + k) * 0.2, k % 2 ? "#5d7a4a" : "#557447", Math.cos(a) * h.r * 0.82, Math.sin(a) * h.r * 0.82, CARD / 2 + LAYER * 3, LAYER);
		}
		out.push(b.done(h.x, h.z, delayAt(h.z) + 0.1 * i, 0, QUAY, 0));
	});
	return out;
}

// the grass behind the quay: a torn printed region of overlapping patches
function green(b: Piece3) {
	for (let i = 0; i < 26; i++) {
		const x = -14 + (i / 25) * 28 + rnd(i + 40) * 0.8;
		const z = -8.6 + rnd(i + 41) * 0.9;
		b.patch(1.0 + rnd(i + 42) * 0.7, "#c9cf9f", x, QUAY + 0.01, z, 1.3);
	}
	b.box(30, 0.012, 7, "#c9cf9f", 0, QUAY + 0.01, -13);
	for (let i = 0; i < 18; i++) b.patch(0.3 + rnd(i + 60) * 0.3, "#b5bd88", -12 + rnd(i + 61) * 24, QUAY + 0.02, -9.8 - rnd(i + 62) * 3, 1.6);
}

// a wooden jetty on posts into the basin (built, open: deck planks on
// stringers on posts), a bollard at its end
function jetty(x: number, z0: number, len: number): Piece {
	const b = new Piece3();
	const W = 1.0, top = 0.3;
	for (let s = 0; s < len; s += 0.27) b.box(W, 0.05, 0.22, s % 0.54 < 0.27 ? WOOD_L : "#b88d58", 0, top, s + 0.13);
	for (const sx of [-W / 2 + 0.08, W / 2 - 0.08]) {
		b.box(0.08, 0.1, len, WOOD, sx, top - 0.07, len / 2);
		for (let s = 0.3; s < len; s += 1.0) b.cyl(0.07, 0.07, top + 0.25, WOOD_D, sx, top / 2 - 0.05, s, 10);
	}
	b.cyl(0.1, 0.12, 0.3, INK, W / 2 - 0.15, top + 0.17, len - 0.2, 12);
	b.ring(0.18, 0.05, "#d8cfb2", -0.15, top + 0.05, len - 0.4);
	return b.done(x, z0, -1, 0, 0, 1);
}

// a rowing boat at the jetty
function dinghy(x: number, z: number, ry: number): Piece {
	const b = new Piece3();
	b.group([0, 0, 0], [0, 0, 0], [1, 1, 1], t => [[0, Math.sin(t * 1.4 + 2) * 0.02, 0], [Math.sin(t * 1.2) * 0.03, 0, 0], [1, 1, 1]]);
	b.box(1.2, 0.3, 0.55, "#5d7a4a", 0, 0.1, 0);
	b.box(0.55 / Math.SQRT2, 0.3, 0.55 / Math.SQRT2, "#5d7a4a", 0.6, 0.1, 0, 0, Math.PI / 4, 0);
	b.box(1.22, 0.07, 0.57, CREAM, 0, 0.2, 0);
	b.box(1.1, 0.03, 0.44, WOOD_L, 0, 0.24, 0);
	b.box(0.1, 0.05, 0.5, WOOD, -0.1, 0.27, 0);
	b.box(1.3, 0.04, 0.05, WOOD_D, -0.1, 0.3, 0.32, 0, 0, 0.15);
	b.front = 0.36;
	return b.done(x, z, delayAt(z), ry);
}

// a buoy bobbing on the water: cone, band, staff and topmark
function buoy(x: number, z: number, c: string, seed: number): Piece {
	const b = new Piece3();
	b.group([0, 0, 0], [0, 0, 0], [1, 1, 1], t => [[0, Math.sin(t * 1.6 + seed) * 0.04, 0], [Math.sin(t * 1.3 + seed) * 0.08, 0, Math.cos(t * 1.1 + seed) * 0.08], [1, 1, 1]]);
	b.cyl(0.18, 0.32, 0.5, c, 0, 0.2, 0, 16);
	b.cyl(0.25, 0.28, 0.12, CREAM, 0, 0.2, 0, 16);
	b.box(0.05, 0.4, 0.05, INK, 0, 0.62, 0);
	b.disc(0.1, c, 0, 0.85, 0);
	b.front = 0.34;
	return b.done(x, z, delayAt(z), 0);
}

// a harbour crane: post, raised jib, rope, a hanging crate
function crane(x: number, z: number): Piece {
	const b = new Piece3();
	b.box(0.5, 0.25, 0.5, "#4a4e5a", 0, 0.12, 0);
	b.box(0.18, 2.6, 0.18, WOOD_D, 0, 1.4, 0);
	b.box(0.22, 0.22, 0.22, INK, 0, 2.7, 0);
	b.box(2.0, 0.12, 0.12, WOOD, 0.85, 2.95, 0, 0, 0, 0.3);
	b.box(0.9, 0.05, 0.05, INK, 0.45, 2.1, 0, 0, 0, 1.0);
	b.box(0.025, 1.2, 0.025, INK, 1.78, 2.65, 0);
	b.box(0.5, 0.36, 0.4, "#3f6c8a", 1.78, 1.85, 0);
	b.box(0.5, 0.04, LAYER, CREAM, 1.78, 1.85, 0.2 + LAYER);
	b.box(0.5, 0.04, LAYER, CREAM, 1.78, 1.95, 0.2 + LAYER);
	b.front = 0.3;
	return b.done(x, z, late(z, 5), -0.25, QUAY);
}

// a fish stall: a counter with plank front, a striped awning on posts,
// fish on ice, a sign
function stall(x: number, z: number): Piece {
	const b = new Piece3();
	b.box(1.7, 0.8, 0.7, WOOD_L, 0, 0.4, 0);
	for (let i = 0; i < 6; i++) b.box(0.03, 0.76, LAYER, WOOD, -0.7 + i * 0.28, 0.4, 0.35 + LAYER / 2);
	b.box(1.6, 0.05, 0.6, "#dfe6e2", 0, 0.82, 0);
	for (let i = 0; i < 4; i++) {
		b.box(0.26, 0.08, 0.12, "#8fa4ad", -0.55 + i * 0.36, 0.88, 0.08 - (i % 2) * 0.16, 0, 0.2 * (i % 2 ? 1 : -1), 0);
		b.box(0.06, 0.08, 0.1, "#6d8494", -0.42 + i * 0.36, 0.88, 0.08 - (i % 2) * 0.16);
	}
	for (const px of [-0.82, 0.82]) b.box(0.07, 1.9, 0.07, WOOD_D, px, 0.95, -0.3);
	b.group([0, 1.95, 0.05], [0.45, 0, 0]);
	for (let i = 0; i < 7; i++) b.box(0.27, 0.04, 0.9, i % 2 ? CREAM : RED, -0.81 + i * 0.27, 0, 0);
	for (let i = 0; i < 7; i++) b.disc(0.135, i % 2 ? CREAM : RED, -0.81 + i * 0.27, -0.02, 0.45, LAYER, false).s = [1, 1, 1];
	b.group([0, 0, 0]);
	b.box(0.9, 0.3, CARD, CREAM, 0, 2.3, -0.35);
	b.box(0.78, 0.2, LAYER, NAVY, 0, 2.3, -0.35 + CARD / 2 + LAYER / 2);
	b.disc(0.06, CREAM, -0.15, 2.3, -0.35 + CARD / 2 + LAYER * 1.5, LAYER);
	b.box(0.2, 0.08, LAYER, CREAM, 0.0, 2.3, -0.35 + CARD / 2 + LAYER * 1.5);
	b.front = 0.5;
	return b.done(x, z, late(z, 9), -0.15, QUAY);
}

// a net drying on a rack, its floats along the top
function netRack(x: number, z: number): Piece {
	const b = new Piece3();
	for (const px of [-0.75, 0.75]) b.box(0.09, 1.5, 0.09, WOOD_D, px, 0.75, 0);
	b.box(1.7, 0.08, 0.09, WOOD_D, 0, 1.45, 0);
	b.box(1.4, 1.0, CARD * 0.6, "#4d6b5a", 0, 0.9, 0);
	for (let i = 0; i < 6; i++) b.box(0.025, 0.98, LAYER, "#9fb5a4", -0.6 + i * 0.24, 0.9, CARD * 0.3 + LAYER / 2);
	for (let i = 0; i < 4; i++) b.box(1.38, 0.025, LAYER, "#9fb5a4", 0, 0.55 + i * 0.24, CARD * 0.3 + LAYER);
	for (let i = 0; i < 5; i++) b.disc(0.08, "#e58a3c", -0.56 + i * 0.28, 1.38, CARD * 0.3 + LAYER * 2, 0.05);
	b.front = 0.1;
	return b.done(x, z, late(z, 3), 0.1, QUAY);
}

// a fisher: a small paper model in an oilskin and sou'wester, for scale
function fisher(x: number, z: number, coat: string, ry: number, seed: number): Piece {
	const b = new Piece3();
	b.box(0.13, 0.36, 0.14, NAVY, -0.08, 0.18, 0);
	b.box(0.13, 0.36, 0.14, NAVY, 0.08, 0.18, 0);
	b.box(0.15, 0.06, 0.2, INK, -0.08, 0.03, 0.03);
	b.box(0.15, 0.06, 0.2, INK, 0.08, 0.03, 0.03);
	b.box(0.4, 0.44, 0.24, coat, 0, 0.58, 0);
	b.box(0.11, 0.38, 0.13, coat, -0.27, 0.6, 0, 0, 0, -0.12);
	b.box(0.11, 0.38, 0.13, coat, 0.27, 0.6, 0, 0, 0, 0.12);
	b.box(0.04, 0.36, LAYER, INK, 0, 0.58, 0.12 + LAYER / 2);
	b.box(0.26, 0.26, 0.24, "#e9c19c", 0, 0.93, 0);
	b.box(0.04, 0.04, LAYER, INK, -0.06, 0.95, 0.12 + LAYER / 2);
	b.box(0.04, 0.04, LAYER, INK, 0.06, 0.95, 0.12 + LAYER / 2);
	b.box(0.08, 0.03, LAYER, "#c2553a", 0, 0.88, 0.12 + LAYER / 2);
	b.box(0.42, 0.04, 0.4, coat, 0, 1.08, -0.03);
	b.cone(0.17, 0.16, coat, 0, 1.17, 0, 10);
	b.front = 0.16;
	return b.done(x, z, late(z, seed), ry, QUAY);
}

// a bench and potted flowers by the white house
function bench(x: number, z: number): Piece {
	const b = new Piece3();
	b.box(1.0, 0.06, 0.32, WOOD_L, 0, 0.36, 0);
	b.box(1.0, 0.22, 0.05, WOOD_L, 0, 0.58, -0.15);
	for (const px of [-0.42, 0.42]) b.box(0.06, 0.36, 0.3, WOOD_D, px, 0.18, 0);
	b.cyl(0.14, 0.1, 0.24, "#b5603c", 0.75, 0.12, 0.05, 14);
	b.disc(0.17, "#6d8c57", 0.75, 0.38, 0.05);
	b.disc(0.06, "#f2c14e", 0.72, 0.42, 0.05 + CARD / 2 + LAYER);
	b.disc(0.06, "#d8624a", 0.8, 0.34, 0.05 + CARD / 2 + LAYER);
	b.front = 0.22;
	return b.done(x, z, late(z, 11), 0.05, QUAY);
}

// a rope coil and a life ring lying on the quay (printed, flat)
function quayPrints(b: Piece3) {
	b.ring(0.2, 0.05, "#d8cfb2", -2.6, QUAY + 0.05, -2.0);
	b.ring(0.11, 0.045, "#c4b994", -2.6, QUAY + 0.06, -2.0);
	b.ring(0.18, 0.06, "#d8cfb2", 6.6, QUAY + 0.06, 0.2);
}

// a gull gliding in a wide slow circle, wings in a shallow V
function gull(cx: number, cz: number, R: number, y: number, speed: number, phase: number): Piece {
	const b = new Piece3();
	const path = (t: number) => {
		const a = phase + t * speed;
		return [[cx + Math.cos(a) * R, y + Math.sin(t * 0.7 + phase) * 0.15, cz + Math.sin(a) * R], [0, -a, Math.sin(t * 0.9 + phase) * 0.12]];
	};
	b.group([0, 0, 0], [0, 0, 0], [1, 1, 1], t => [path(t)[0], path(t)[1], [0.6, 0.6, 0.6]]);
	b.box(0.12, 0.1, 0.4, CREAM, 0, 0, 0);
	b.box(0.48, 0.03, 0.18, CREAM, -0.26, 0.07, 0.02, 0, 0, 0.3);
	b.box(0.48, 0.03, 0.18, CREAM, 0.26, 0.07, 0.02, 0, 0, -0.3);
	b.box(0.14, 0.035, 0.12, "#5a5d66", -0.47, 0.13, 0.02, 0, 0, 0.3);
	b.box(0.14, 0.035, 0.12, "#5a5d66", 0.47, 0.13, 0.02, 0, 0, -0.3);
	b.box(0.05, 0.05, 0.1, OCHRE, 0, 0, 0.24);
	return b.done(0, 0, -1, 0, 0, 0);
}

export function dressing(): Piece[] {
	const ground = new Piece3();
	green(ground);
	quayPrints(ground);
	return [
		ground.done(0, 0, -1, 0, 0, 0),
		...hills(),
		tree(-6.6, -4.4, 1, 1.0), tree(-7.6, -6.4, 2, 1.25), tree(5.9, -4.6, 3, 1.1), tree(-0.3, -6.8, 4, 0.9), tree(8.2, -6.6, 5, 1.3),
		bollard(-4.6, -1.65), bollard(-2.0, -1.65), bollard(1.4, -1.65), bollard(3.2, 0.65), bollard(6.0, 0.65), bollard(8.6, 0.65),
		bollard(-6.9, 0.2), barrels(-5.9, -2.4, 3, 1), barrels(7.5, -0.4, 2, 2),
		crates(2.6, -1.9, 3, 0.15), crates(5.0, -2.2, 4, -0.2),
		lamp(-2.9, -2.1), lamp(5.8, -1.0),
		jetty(-0.95, -1.4, 3.3), dinghy(0.35, 1.0, -0.3),
		buoy(-1.6, 6.0, RED, 1), buoy(3.0, 6.8, "#3a6a52", 2), buoy(8.6, 4.6, RED, 3),
		crane(3.7, 0.1), stall(8.4, -1.8), netRack(7.0, -3.4),
		fisher(-0.9, 1.35, OCHRE, 0.4, 1), fisher(2.2, -2.5, OCHRE, -0.5, 2), fisher(7.9, -0.95, RED, -0.3, 3),
		bench(-4.7, -2.55),
		gull(-3, -2, 4.0, 6.5, 0.22, 0.6), gull(2.5, -1.5, 5.0, 7.2, 0.18, 2.4), gull(5, 1, 3.2, 5.8, 0.26, 4.1),
	];
}
