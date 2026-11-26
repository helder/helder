/*
PAPER SPEC
BRIEF    a pop-up harbour town folding up out of the page: a few houses (4), a lighthouse, boats on printed water;
         a bright, breezy northern-coast morning; calm, toy-like.
SUBJECT  a little quay town of gabled harbour houses around a basin, a banded lighthouse on the mole's round end;
         the eye goes first to the lighthouse and the row of coloured gables behind the boats.
STOCK    smooth cardstock for pieces, the page a pale sandstone card; prints are cut layers 0.014 thick.
PALETTE  quay ground #e7dcc3 / joints #cdbf9f, water #86aab0 with scallops #6e939c and crests #e9e2cf,
         lead family harbour reds #c2553a / #9e3d2c, ochre #dca443, slate blue #4e6e8c, cream #f1e6cc,
         ink #3a2a22, shadow tint amber on the quay, teal on the water.
LIGHT    warm key #fff0da from the left-front, ~55 deg off the camera axis, ~50 deg up; frontal fill ~0.3; warm
         hemisphere for amber shadows.
LENS     fov ~28 deg, camera ~45 deg down; no blur pass in markup (honest gap), ground past every edge.
GROUND   a stone quay (built masonry, named by the brief) with printed paving, around a printed water basin.
LAYOUT   the quay bends round the basin: town row at the back, a right quay jutting forward, the mole at left.
MOTION   every piece on a crease at its base, rising from lying back; front to back stagger ~0.07 s/unit;
         rise upright 0.17 s, 12 % overshoot, still by ~0.9 s.
LIFE     chimney smoke, gulls wheeling, boats rocking, a bobbing buoy.
TYPES    houses: box folds with a gable prism; lighthouse: a tapered round fold; boats: hull box folds with a
         prism bow; trees: slotted crosses; hills: nested layered flats.
SOUND    none.
BANNED   gloss, grey shadows, white halos, stamped repeats, sky or horizon.
*/
import { Piece, Piece3, CARD, LAYER, rnd } from "./paper";

export const QUAY = 0.35; // the quay's height over the water
const INK = "#3a2a22";
const CREAM = "#f1e6cc";
const PANE = "#34465a";

// stagger: the nearest pieces lie on top when folded, so they rise first
export function delayAt(z: number): number {
	return 0.15 + Math.max(0, 7 - z) * 0.07;
}

// a window printed on a wall (in the current frame, its face at z):
// frame, pane, glazing bars, shutters, sill, a flower box
function windowOn(b: Piece3, x: number, y: number, z: number, shutter: string, box: string) {
	const w = 0.42, h = 0.58;
	b.box(w + 0.1, h + 0.1, LAYER, CREAM, x, y, z);
	b.box(w - 0.02, h - 0.02, LAYER, PANE, x, y, z + LAYER);
	b.box(0.05, h - 0.02, LAYER, CREAM, x, y, z + LAYER * 2);
	b.box(w - 0.02, 0.05, LAYER, CREAM, x, y + h * 0.08, z + LAYER * 2);
	if (shutter !== "") {
		b.box(0.17, h, LAYER, shutter, x - (w / 2 + 0.15), y, z);
		b.box(0.17, h, LAYER, shutter, x + (w / 2 + 0.15), y, z);
	}
	b.box(w + 0.2, 0.07, 0.08, CREAM, x, y - (h / 2 + 0.07), z + 0.03);
	if (box !== "") {
		b.box(w + 0.06, 0.14, 0.1, box, x, y - (h / 2 + 0.17), z + 0.05);
		b.disc(0.07, "#d8624a", x - w / 4, y - (h / 2 + 0.06), z + 0.11);
		b.disc(0.07, "#f2c14e", x + w / 5, y - (h / 2 + 0.05), z + 0.11);
	}
}

export type HouseSpec = {
	x: number; z: number; w: number; h: number; d: number; ry: number;
	wall: string; plinth: string; roof: string; roofDark: string; accent: string;
	pitch: number; floors: number; door: number; chimney: number; seed: number;
};

// a harbour house: a box fold with a gable prism and a two-slope roof, its
// front printed as a cut-paper collage
function house(s: HouseSpec): Piece {
	const b = new Piece3();
	const a = Math.atan(s.pitch);
	const half = s.w / 2;
	const slope = half / Math.cos(a) + 0.22;
	const gable = half * s.pitch;
	const floorH = (s.h - 0.4) / s.floors;
	const cols = s.w > 2.3 ? 3 : 2;
	const colX = (i: number) => (cols === 3 ? (i - 1) * s.w * 0.31 : (i - 0.5) * s.w * 0.46);
	const front = CARD / 2;
	b.front = 0.2;
	const chimX = half * 0.5 * (s.chimney ? 1 : -1);
	// the fold: walls, gable prism, chimney
	b.box(s.w, s.h, s.d, s.wall, 0, s.h / 2, -s.d / 2);
	b.tri(s.w, gable, s.d, s.wall, 0, s.h, -s.d / 2);
	b.box(0.34, 0.9, 0.34, s.plinth, chimX, s.h + gable * 0.55 + 0.3, -s.d * 0.6);
	b.box(0.42, 0.08, 0.42, INK, chimX, s.h + gable * 0.55 + 0.78, -s.d * 0.6);
	// the printed front: plinth with joints, string course, eaves band
	b.box(s.w, 0.4, LAYER, s.plinth, 0, 0.2, front);
	const joints = Math.round(s.w / 0.38);
	for (let i = 0; i < joints; i++) b.box(0.03, 0.36, LAYER, s.roofDark, -half + 0.38 * (i + 0.5), 0.2, front + LAYER);
	if (s.floors > 1) b.box(s.w, 0.09, LAYER, s.accent, 0, 0.4 + floorH, front);
	b.box(s.w + 0.04, 0.1, 0.05, CREAM, 0, s.h - 0.02, front);
	for (let f = 0; f < s.floors; f++)
		for (let i = 0; i < cols; i++) {
			if (f === 0 && i === s.door) continue;
			windowOn(b, colX(i), 0.4 + floorH * (f + 0.55), front, (f + i + s.seed) % 2 === 0 ? s.accent : "", f === 1 && i !== 1 ? "#5d7a4a" : "");
		}
	// the door: frame, leaf, rail, fanlight, knob
	const dx = colX(s.door);
	b.box(0.62, 1.06, LAYER, CREAM, dx, 0.9, front);
	b.box(0.48, 0.88, LAYER, s.accent, dx, 0.84, front + LAYER);
	b.box(0.36, 0.04, LAYER, s.roofDark, dx, 0.9, front + LAYER * 2);
	b.disc(0.2, PANE, dx, 1.38, front + LAYER, LAYER, true);
	b.disc(0.04, "#e3b54a", dx + 0.15, 0.82, front + LAYER * 2, LAYER);
	// the gable's round window
	b.disc(0.24, CREAM, 0, s.h + gable * 0.36, front, LAYER);
	b.disc(0.17, PANE, 0, s.h + gable * 0.36, front + LAYER, LAYER);
	// the roof's two slopes, each with shingle rows and a dark eave edge
	for (const sign of [1, -1]) {
		b.group([-sign * half / 2, s.h + gable / 2 + 0.05, -s.d / 2], [0, 0, sign * a]);
		b.box(slope, 0.1, s.d + 0.3, s.roof);
		for (const f of [0.2, 0.45, 0.7]) b.box(0.07, 0.02, s.d + 0.3, s.roofDark, (f - 0.5) * slope, 0.06, 0);
		b.box(slope, 0.12, 0.03, s.roofDark, 0, 0, (s.d + 0.3) / 2);
	}
	// a window on each side wall
	for (const sign of [-1, 1]) {
		b.group([sign * (half + CARD / 2), 0.4 + floorH * 1.55, -s.d / 2], [0, sign * Math.PI / 2, 0]);
		windowOn(b, 0, 0, 0, s.accent, "");
	}
	// smoke curling from the chimney: paper puffs that rise, drift and
	// shrink back into nothing (they grow and shrink, never pop)
	if (s.seed % 2 === 1) {
		const top = s.h + gable * 0.55 + 0.8;
		for (let k = 0; k < 3; k++) {
			b.group([0, 0, 0], [0, 0, 0], [1, 1, 1], t => {
				const ph = (t * 0.22 + k / 3 + s.seed * 0.1) % 1;
				const sc = 0.08 + Math.sin(Math.PI * ph) * 0.92;
				return [[chimX + ph * 0.9 + Math.sin(ph * 5) * 0.1, top + ph * 1.7, -s.d * 0.6 + ph * 0.4], [0, 0, ph * 0.6], [sc, sc, 1]];
			});
			b.disc(0.24, "#efe7d8", 0, 0, 0, CARD);
			b.disc(0.15, "#f8f2e6", -0.05, 0.05, CARD / 2 + LAYER, LAYER);
		}
	}
	return b.done(s.x, s.z, delayAt(s.z), s.ry, QUAY);
}

export const houses: HouseSpec[] = [
	{ x: -4.2, z: -3.6, w: 2.2, h: 3.0, d: 2.2, ry: 0.05, wall: "#f1e6cc", plinth: "#a99a80", roof: "#c2553a", roofDark: "#8e3a28", accent: "#4e6e8c", pitch: 1.25, floors: 2, door: 0, chimney: 1, seed: 1 },
	{ x: -1.7, z: -4.2, w: 2.0, h: 3.7, d: 2.0, ry: 0, wall: "#4e6e8c", plinth: "#3d5670", roof: "#3c3a44", roofDark: "#26252c", accent: "#dca443", pitch: 1.6, floors: 3, door: 1, chimney: 0, seed: 2 },
	{ x: 0.9, z: -3.8, w: 2.6, h: 2.7, d: 2.2, ry: -0.04, wall: "#dca443", plinth: "#a87a2c", roof: "#9e3d2c", roofDark: "#6f2a1e", accent: "#c2553a", pitch: 1.0, floors: 2, door: 1, chimney: 1, seed: 3 },
	{ x: 3.5, z: -3.3, w: 2.1, h: 3.3, d: 2.1, ry: -0.1, wall: "#b5492f", plinth: "#7d3322", roof: "#4a4e5a", roofDark: "#2e313a", accent: "#f1e6cc", pitch: 1.4, floors: 2, door: 0, chimney: 0, seed: 4 },
];

// the lighthouse: a tapered round fold with red bands, gallery and lantern
function lighthouse(x: number, z: number): Piece {
	const b = new Piece3();
	const H = 5.2, r0 = 0.78, r1 = 0.56;
	const rAt = (y: number) => r0 + (r1 - r0) * (y / H);
	const RED = "#b8432f";
	b.cyl(r1, r0, H, CREAM, 0, H / 2, 0);
	for (const band of [[1.1, 1.9], [2.9, 3.7]])
		b.cyl(rAt(band[1]) + 0.015, rAt(band[0]) + 0.015, band[1] - band[0], RED, 0, (band[0] + band[1]) / 2, 0);
	b.cyl(0.95, 1.0, 0.3, "#a99a80", 0, 0.15, 0);
	b.box(0.42, 0.8, LAYER, INK, 0, 0.7, rAt(0.7) + 0.02);
	b.disc(0.21, INK, 0, 1.1, rAt(1.1) + 0.02, LAYER, true);
	b.box(0.22, 0.32, LAYER, PANE, 0, 2.45, rAt(2.45) + 0.01);
	b.box(0.22, 0.32, LAYER, PANE, 0, 4.25, rAt(4.25) + 0.01);
	b.cyl(0.86, 0.86, 0.12, INK, 0, H + 0.06, 0);
	const lamp = b.cyl(0.42, 0.42, 0.66, "#f6d77a", 0, H + 0.45, 0, 12);
	lamp.glow = 0.4;
	for (let i = 0; i < 6; i++) {
		const t = (i * Math.PI) / 3;
		b.box(0.05, 0.66, 0.05, INK, Math.sin(t) * 0.42, H + 0.45, Math.cos(t) * 0.42, 0, t, 0);
	}
	b.cone(0.6, 0.62, RED, 0, H + 1.08, 0);
	b.disc(0.09, INK, 0, H + 1.44, 0);
	b.front = 1.02;
	return b.done(x, z, delayAt(z) + 0.1, 0, QUAY);
}

export type BoatSpec = { x: number; z: number; ry: number; hull: string; band: string; cabin: string; len: number; sail: string; seed: number };

// a boat: a hull box fold with a pointed bow, a wheelhouse or a sail; it rocks
function boat(s: BoatSpec): Piece {
	const b = new Piece3();
	// bobbing on the swell: a slow heave, a roll and a gentle pitch, each boat on its own phase
	b.group([0, 0, 0], [0, 0, 0], [1, 1, 1], t => {
		const ph = t * 1.15 + s.seed * 2.1;
		return [[0, Math.sin(ph) * 0.09 + Math.sin(ph * 2.3) * 0.02, 0], [Math.sin(ph * 0.8 + 1.2) * 0.05, 0, Math.sin(ph + 0.7) * 0.07], [1, 1, 1]];
	});
	const L = s.len, W = 0.9, H = 0.62;
	b.box(L, H, W, s.hull, 0, H / 2 - 0.12, 0);
	const bow = b.box(W / Math.SQRT2, H, W / Math.SQRT2, s.hull, L / 2, H / 2 - 0.12, 0, 0, Math.PI / 4, 0);
	bow.s = [1, 1, 1];
	b.box(L + 0.02, 0.12, W + 0.02, s.band, 0, H - 0.2, 0);
	b.box(L - 0.1, 0.05, W - 0.12, "#b89a6e", 0, H - 0.11, 0);
	if (s.sail !== "") {
		b.box(0.07, 2.6, 0.07, INK, 0.15, H + 1.2, 0);
		b.tri(1.3, 2.2, CARD, s.sail, -0.5, H + 0.12, 0);
		b.box(1.3, 0.06, 0.06, INK, -0.5, H + 0.12, 0);
		b.box(0.3, 0.16, LAYER, "#c2553a", 0.33, H + 2.35, 0);
	} else {
		b.box(0.9, 0.72, 0.66, s.cabin, -0.25, H + 0.3, 0);
		b.box(1.05, 0.08, 0.8, INK, -0.25, H + 0.7, 0);
		b.box(0.32, 0.26, LAYER, PANE, -0.25, H + 0.36, 0.34);
		b.box(0.06, 1.5, 0.06, INK, 0.55, H + 0.7, 0);
		b.box(0.32, 0.18, LAYER, "#dca443", 0.73, H + 1.35, 0);
		b.disc(0.12, CREAM, 0.35, H - 0.2, W / 2 + 0.03, 0.05);
		b.disc(0.07, "#c2553a", 0.35, H - 0.2, W / 2 + 0.06, 0.05);
	}
	b.front = W / 2 + 0.1;
	return b.done(s.x, s.z, delayAt(s.z), s.ry);
}

export const boats: BoatSpec[] = [
	{ x: -3.4, z: 2.6, ry: 0.18, hull: "#c2553a", band: CREAM, cabin: CREAM, len: 2.4, sail: "", seed: 1 },
	{ x: 0.6, z: 4.4, ry: -0.12, hull: "#2f4a63", band: "#dca443", cabin: CREAM, len: 2.2, sail: "#efe3c6", seed: 2 },
	{ x: 4.2, z: 2.9, ry: 0.32, hull: "#e0b04c", band: "#3a5f7a", cabin: "#c2553a", len: 2.0, sail: "", seed: 3 },
];

// the page: the printed water (base, scallop waves, crests) and the quay,
// built masonry around the basin with its top printed with paving
function page(): Piece {
	const b = new Piece3();
	b.box(60, 0.02, 60, "#86aab0", 0, 0, 0);
	for (let i = 0; i < 70; i++) {
		const x = -13 + rnd(i) * 26, z = rnd(i + 100) * 13;
		const r = 0.32 + rnd(i + 200) * 0.22;
		b.patch(r, "#6e939c", x, 0.012, z, 1.4, true).r = [0, Math.PI / 2, 0];
		b.patch(r * 0.86, "#86aab0", x, 0.022, z + r * 0.2, 1.4, true).r = [0, Math.PI / 2, 0];
		if (rnd(i + 300) > 0.55) b.patch(r * 0.3, "#e9e2cf", x + r * 1.0, 0.026, z - r * 0.05, 1.5, true).r = [0, Math.PI / 2, 0];
	}
	const H = QUAY;
	const block = (x0: number, x1: number, z0: number, z1: number) => {
		b.box(x1 - x0, H, z1 - z0, "#e7dcc3", (x0 + x1) / 2, H / 2, (z0 + z1) / 2);
		b.box(x1 - x0, H - 0.04, LAYER, "#bdae90", (x0 + x1) / 2, H / 2 - 0.02, z1 + LAYER / 2);
		const lo = Math.max(x0, -14), hi = Math.min(x1, 14);
		for (let x = lo + 0.3; x < hi; x += 0.55) b.box(0.03, H - 0.06, LAYER, "#8f826a", x, H / 2, z1 + LAYER * 1.5);
	};
	block(-30, 30, -30, -1.4);
	block(2.2, 30, -1.4, 0.9);
	block(-8.6, -5.4, -1.4, 0.4);
	block(-7.6, -6.2, 0.4, 2.8);
	b.cyl(1.5, 1.5, H, "#e7dcc3", -6.9, H / 2, 3.2, 32);
	b.cyl(1.52, 1.52, H - 0.04, "#bdae90", -6.9, H / 2 - 0.02, 3.2, 32);
	for (let i = 0; i < 46; i++) {
		const x = -13 + rnd(i + 500) * 26, z = -12 + rnd(i + 600) * 10.4;
		b.box(0.5 + rnd(i + 700) * 0.4, 0.01, 0.35 + rnd(i + 800) * 0.25, "#d6c9ab", x, H + 0.005, z, 0, rnd(i + 900) * 0.3, 0);
	}
	return b.done(0, 0, -1, 0, 0, 0);
}

// the lighthouse on the mole's round end (its beam is drawn by the scene)
export const LIGHTHOUSE = lighthouse(-6.9, 3.2);

// every piece of the harbour, the page first
export const pieces: Piece[] = [page(), ...houses.map(house), LIGHTHOUSE, ...boats.map(boat)];
