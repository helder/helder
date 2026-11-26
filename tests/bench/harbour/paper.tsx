// Paper kit for the harbour: colours, the hinge spring and a builder of
// pieces. Everything is a sheet with thickness (CARD), printed by laying
// thinner cut layers on it (law 4); each piece rises about a crease at its
// base (law 10). Pieces are data (groups of primitives), drawn by one
// literal inside the <Scene> (app.tsx).
import { vec4 } from "helder/gfx";
import { Vec4 } from "helder/math";

// sRGB hex to the renderer's linear colour
export function ink(hex: string): Vec4 {
	const n = parseInt(hex.slice(1), 16);
	const lin = (c: number) => Math.pow(c / 255, 2.2);
	return vec4(lin((n >> 16) & 255), lin((n >> 8) & 255), lin(n & 255), 1);
}

export const CARD = 0.06; // card thickness: ~1.7 % of a 3.6 figure
export const LAYER = 0.014; // one printed layer's lift off the sheet

// the spring of a card rising from flat: 0 flat, 1 upright; upright at
// ~0.17 s, ~12 % overshoot at 0.35 s, a small quiver, still by ~0.9 s
export function rise(t: number, delay: number): number {
	if (delay < 0) return 1;
	const s = t - delay;
	if (s <= 0) return 0;
	return 1 - Math.exp(-6 * s) * Math.cos(9 * s);
}

// the crease's angle: lying back (top away from the camera) to upright
export function crease(t: number, delay: number): number {
	return -(Math.PI / 2) * (1 - rise(t, delay));
}

export type V3 = number[];
export type Prim = {
	k: string; // "box" | "cyl" | "cone"
	p: V3; r: V3; s: V3;
	w: number; h: number; d: number; // box
	rt: number; rb: number; seg: number; th: number; ts: number; // cylinder, cone
	c: Vec4; glow: number;
};
export type Motion = (t: number) => V3[]; // [position, rotation, scale]
export type Group = { p: V3; r: V3; s: V3; prims: Prim[]; anim: Motion | null };
// front: how far the piece reaches toward the camera from its centre; its
// crease is put there, so folded flat it lies wholly under the page
export type Piece = { x: number; y: number; z: number; ry: number; delay: number; outline: number; front: number; groups: Group[] };

const ZERO = [0, 0, 0], ONE = [1, 1, 1];

function prim(k: string, c: string): Prim {
	return { k, p: ZERO, r: ZERO, s: ONE, w: 1, h: 1, d: 1, rt: 1, rb: 1, seg: 24, th: Math.PI * 2, ts: 0, c: ink(c), glow: 0 };
}

// a piece under construction: its groups (frames) of cards
export class Piece3 {
	groups: Group[] = [];
	g: Group;
	front = 0;
	constructor() {
		this.g = this.group(ZERO);
	}
	// a new frame inside the piece; later cards go into it
	group(p: V3, r: V3 = ZERO, s: V3 = ONE, anim: Motion | null = null): Group {
		const g: Group = { p, r, s, prims: [], anim };
		this.groups.push(g);
		this.g = g;
		return g;
	}
	// a card or a block: w x h x d centred on (x, y, z)
	box(w: number, h: number, d: number, c: string, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0): Prim {
		const q = prim("box", c);
		q.w = w; q.h = h; q.d = d; q.p = [x, y, z]; q.r = [rx, ry, rz];
		this.g.prims.push(q);
		return q;
	}
	// a round card standing up, facing +z (half: its upper half)
	disc(r: number, c: string, x = 0, y = 0, z = 0, d = CARD, half = false): Prim {
		const q = prim("cyl", c);
		q.rt = r; q.rb = r; q.h = d; q.p = [x, y, z]; q.r = [Math.PI / 2, 0, 0]; q.seg = 28;
		if (half) {
			q.th = Math.PI;
			q.ts = -Math.PI / 2;
			q.r = [-Math.PI / 2, 0, 0];
		}
		this.g.prims.push(q);
		return q;
	}
	// a printed patch lying on the page, stretched sx along x
	patch(r: number, c: string, x: number, y: number, z: number, sx = 1, half = false): Prim {
		const q = prim("cyl", c);
		q.rt = r; q.rb = r; q.h = 0.012; q.p = [x, y, z]; q.s = [sx, 1, 1]; q.seg = 28;
		if (half) q.th = Math.PI;
		this.g.prims.push(q);
		return q;
	}
	// a round fold: a cylinder (tapered: rt at the top, rb at the foot)
	cyl(rt: number, rb: number, h: number, c: string, x = 0, y = 0, z = 0, seg = 24): Prim {
		const q = prim("cyl", c);
		q.rt = rt; q.rb = rb; q.h = h; q.p = [x, y, z]; q.seg = seg;
		this.g.prims.push(q);
		return q;
	}
	// a ring lying on the page (a rope coil, a life ring)
	ring(r: number, tube: number, c: string, x = 0, y = 0, z = 0, rx = Math.PI / 2): Prim {
		const q = prim("torus", c);
		q.rb = r; q.d = tube; q.p = [x, y, z]; q.r = [rx, 0, 0];
		this.g.prims.push(q);
		return q;
	}
	cone(r: number, h: number, c: string, x = 0, y = 0, z = 0, seg = 12): Prim {
		const q = prim("cone", c);
		q.rb = r; q.h = h; q.p = [x, y, z]; q.seg = seg;
		this.g.prims.push(q);
		return q;
	}
	// a triangle (a gable, a sail, a pennant) standing in the xy plane facing
	// +z: base w wide at y, apex h above it, d thick
	tri(w: number, h: number, d: number, c: string, x = 0, y = 0, z = 0): Prim {
		const q = prim("cyl", c);
		q.rt = 1; q.rb = 1; q.h = 1; q.seg = 3;
		q.s = [w / 2 / 0.8660254, d, h / 1.5];
		q.r = [-Math.PI / 2, 0, 0];
		q.p = [x, y + h / 3, z];
		this.g.prims.push(q);
		return q;
	}
	// the piece placed on the page at (x, z), turned ry, rising at delay
	done(x: number, z: number, delay: number, ry = 0, y = 0, outline = 1): Piece {
		return { x, y, z, ry, delay, outline, front: this.front, groups: this.groups.filter(g => g.prims.length > 0) };
	}
}

// a seeded random number in [0, 1)
export function rnd(seed: number): number {
	const s = Math.sin(seed * 127.1 + 311.7) * 43758.5453;
	return s - Math.floor(s);
}
