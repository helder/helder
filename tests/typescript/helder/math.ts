// helder's math types from TypeScript (tests/view's MathProbe): helder/gfx's
// Vec2, Vec3, Vec4, Mat4 and Quat given to Haxe and back, by value (a value
// given is the program's still, a value read a copy).
import { MathProbe } from "./test-renderer";
import { Vec2, Vec3, Vec4, Quat, Mat4 } from "helder/math";

const v = new Vec3(1, 2, 3);
const s = MathProbe.scaled(v, 2);
console.log(s.x, s.y, s.z, v.x, s instanceof Vec3);
console.log(MathProbe.sum(new Vec2(1, 2), new Vec4(3, 4, 5, 6)));
const m = MathProbe.translation(1, 2, 3);
console.log(m.c0.x, m.c1.y, m.c3.x, m.c3.y, m.c3.z, m.c3.w);
const p = MathProbe.apply(m, new Vec4(1, 1, 1, 1));
console.log(p.x, p.y, p.z, p.w, p.add(1).x);
const q = MathProbe.spin(Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 2), Quat.identity());
console.log(q.x, q.y, q.z.toFixed(4), q.w.toFixed(4));
const probe = new MathProbe(new Vec3(0, 0, 1));
const a = probe.at;
probe.moved(new Vec3(1, 0, 0));
console.log(a.x, probe.at.x, probe.at.z);
probe.at = new Vec3(5, 6, 7);
console.log(probe.at.y, probe.moved(new Vec3(1, 1, 1)).z);
probe.turn = Quat.fromEuler(0, Math.PI, 0);
console.log(probe.turn.y.toFixed(4), probe.turn.w.toFixed(4));
// struct values a TypeScript function returns into Haxe: each its own
// Vec2, Vec3, Vec4, Quat or Mat4, read by Haxe where it calls it
console.log(MathProbe.made2((x, y) => new Vec2(x + 1, y + 1)));
const graded = MathProbe.mapped3(new Vec3(1, 2, 3), 4, (c, i) => new Vec3(c.y, c.z, c.x + i));
console.log(graded.x, graded.y, graded.z);
const four = MathProbe.made4(i => new Vec4(i, 2 * i, 3, 4));
console.log(four.x, four.y, four.z, four.w);
const turned = MathProbe.turned(a => Quat.axisAngle(new Vec3(0, 1, 0), a));
console.log(turned.y.toFixed(4), turned.w.toFixed(4));
const placed = MathProbe.placed((x, y, z) => new Mat4(new Vec4(1, 0, 0, 0), new Vec4(0, 1, 0, 0), new Vec4(0, 0, 1, 0), new Vec4(x, y, z, 1)), new Vec4(0, 0, 0, 1));
console.log(placed.x, placed.y, placed.w);
MathProbe.keep(() => new Vec3(7, 8, 9));
const later = MathProbe.callKept();
console.log(later.x, later.y, later.z);
