// helder/math for TypeScript: written by src/helder/math/typescript.mjs (do not edit).
//
// helder.math's types, the same names: immutable values (Haxe's are
// @:hxmc.struct values; helder's API copies them both ways). The operators
// are methods (a.mul(b), a.add(1); a number's side second: x.mul(2), as
// Haxe's 2 * x prints). helder/gfx's builtins (vec3, dot, normalize, ...)
// build and take them.

export class Vec2 {
	constructor(readonly x: number, readonly y: number) {}
	add(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x + b, this.y + b) : new Vec2(this.x + b.x, this.y + b.y);
	}
	sub(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x - b, this.y - b) : new Vec2(this.x - b.x, this.y - b.y);
	}
	mul(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x * b, this.y * b) : new Vec2(this.x * b.x, this.y * b.y);
	}
	div(b: Vec2 | number): Vec2 {
		return typeof b === "number" ? new Vec2(this.x / b, this.y / b) : new Vec2(this.x / b.x, this.y / b.y);
	}
	neg(): Vec2 {
		return new Vec2(-this.x, -this.y);
	}
	get xx(): Vec2 {
		return new Vec2(this.x, this.x);
	}
	get xy(): Vec2 {
		return new Vec2(this.x, this.y);
	}
	get yx(): Vec2 {
		return new Vec2(this.y, this.x);
	}
	get yy(): Vec2 {
		return new Vec2(this.y, this.y);
	}
	get xxx(): Vec3 {
		return new Vec3(this.x, this.x, this.x);
	}
	get xxy(): Vec3 {
		return new Vec3(this.x, this.x, this.y);
	}
	get xyx(): Vec3 {
		return new Vec3(this.x, this.y, this.x);
	}
	get xyy(): Vec3 {
		return new Vec3(this.x, this.y, this.y);
	}
	get yxx(): Vec3 {
		return new Vec3(this.y, this.x, this.x);
	}
	get yxy(): Vec3 {
		return new Vec3(this.y, this.x, this.y);
	}
	get yyx(): Vec3 {
		return new Vec3(this.y, this.y, this.x);
	}
	get yyy(): Vec3 {
		return new Vec3(this.y, this.y, this.y);
	}
	get xxxx(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.x);
	}
	get xxxy(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.y);
	}
	get xxyx(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.x);
	}
	get xxyy(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.y);
	}
	get xyxx(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.x);
	}
	get xyxy(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.y);
	}
	get xyyx(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.x);
	}
	get xyyy(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.y);
	}
	get yxxx(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.x);
	}
	get yxxy(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.y);
	}
	get yxyx(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.x);
	}
	get yxyy(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.y);
	}
	get yyxx(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.x);
	}
	get yyxy(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.y);
	}
	get yyyx(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.x);
	}
	get yyyy(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.y);
	}
}

export class Vec3 {
	constructor(readonly x: number, readonly y: number, readonly z: number) {}
	add(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x + b, this.y + b, this.z + b) : new Vec3(this.x + b.x, this.y + b.y, this.z + b.z);
	}
	sub(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x - b, this.y - b, this.z - b) : new Vec3(this.x - b.x, this.y - b.y, this.z - b.z);
	}
	mul(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x * b, this.y * b, this.z * b) : new Vec3(this.x * b.x, this.y * b.y, this.z * b.z);
	}
	div(b: Vec3 | number): Vec3 {
		return typeof b === "number" ? new Vec3(this.x / b, this.y / b, this.z / b) : new Vec3(this.x / b.x, this.y / b.y, this.z / b.z);
	}
	neg(): Vec3 {
		return new Vec3(-this.x, -this.y, -this.z);
	}
	get xx(): Vec2 {
		return new Vec2(this.x, this.x);
	}
	get xy(): Vec2 {
		return new Vec2(this.x, this.y);
	}
	get xz(): Vec2 {
		return new Vec2(this.x, this.z);
	}
	get yx(): Vec2 {
		return new Vec2(this.y, this.x);
	}
	get yy(): Vec2 {
		return new Vec2(this.y, this.y);
	}
	get yz(): Vec2 {
		return new Vec2(this.y, this.z);
	}
	get zx(): Vec2 {
		return new Vec2(this.z, this.x);
	}
	get zy(): Vec2 {
		return new Vec2(this.z, this.y);
	}
	get zz(): Vec2 {
		return new Vec2(this.z, this.z);
	}
	get xxx(): Vec3 {
		return new Vec3(this.x, this.x, this.x);
	}
	get xxy(): Vec3 {
		return new Vec3(this.x, this.x, this.y);
	}
	get xxz(): Vec3 {
		return new Vec3(this.x, this.x, this.z);
	}
	get xyx(): Vec3 {
		return new Vec3(this.x, this.y, this.x);
	}
	get xyy(): Vec3 {
		return new Vec3(this.x, this.y, this.y);
	}
	get xyz(): Vec3 {
		return new Vec3(this.x, this.y, this.z);
	}
	get xzx(): Vec3 {
		return new Vec3(this.x, this.z, this.x);
	}
	get xzy(): Vec3 {
		return new Vec3(this.x, this.z, this.y);
	}
	get xzz(): Vec3 {
		return new Vec3(this.x, this.z, this.z);
	}
	get yxx(): Vec3 {
		return new Vec3(this.y, this.x, this.x);
	}
	get yxy(): Vec3 {
		return new Vec3(this.y, this.x, this.y);
	}
	get yxz(): Vec3 {
		return new Vec3(this.y, this.x, this.z);
	}
	get yyx(): Vec3 {
		return new Vec3(this.y, this.y, this.x);
	}
	get yyy(): Vec3 {
		return new Vec3(this.y, this.y, this.y);
	}
	get yyz(): Vec3 {
		return new Vec3(this.y, this.y, this.z);
	}
	get yzx(): Vec3 {
		return new Vec3(this.y, this.z, this.x);
	}
	get yzy(): Vec3 {
		return new Vec3(this.y, this.z, this.y);
	}
	get yzz(): Vec3 {
		return new Vec3(this.y, this.z, this.z);
	}
	get zxx(): Vec3 {
		return new Vec3(this.z, this.x, this.x);
	}
	get zxy(): Vec3 {
		return new Vec3(this.z, this.x, this.y);
	}
	get zxz(): Vec3 {
		return new Vec3(this.z, this.x, this.z);
	}
	get zyx(): Vec3 {
		return new Vec3(this.z, this.y, this.x);
	}
	get zyy(): Vec3 {
		return new Vec3(this.z, this.y, this.y);
	}
	get zyz(): Vec3 {
		return new Vec3(this.z, this.y, this.z);
	}
	get zzx(): Vec3 {
		return new Vec3(this.z, this.z, this.x);
	}
	get zzy(): Vec3 {
		return new Vec3(this.z, this.z, this.y);
	}
	get zzz(): Vec3 {
		return new Vec3(this.z, this.z, this.z);
	}
	get xxxx(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.x);
	}
	get xxxy(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.y);
	}
	get xxxz(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.z);
	}
	get xxyx(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.x);
	}
	get xxyy(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.y);
	}
	get xxyz(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.z);
	}
	get xxzx(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.x);
	}
	get xxzy(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.y);
	}
	get xxzz(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.z);
	}
	get xyxx(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.x);
	}
	get xyxy(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.y);
	}
	get xyxz(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.z);
	}
	get xyyx(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.x);
	}
	get xyyy(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.y);
	}
	get xyyz(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.z);
	}
	get xyzx(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.x);
	}
	get xyzy(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.y);
	}
	get xyzz(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.z);
	}
	get xzxx(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.x);
	}
	get xzxy(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.y);
	}
	get xzxz(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.z);
	}
	get xzyx(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.x);
	}
	get xzyy(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.y);
	}
	get xzyz(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.z);
	}
	get xzzx(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.x);
	}
	get xzzy(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.y);
	}
	get xzzz(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.z);
	}
	get yxxx(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.x);
	}
	get yxxy(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.y);
	}
	get yxxz(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.z);
	}
	get yxyx(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.x);
	}
	get yxyy(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.y);
	}
	get yxyz(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.z);
	}
	get yxzx(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.x);
	}
	get yxzy(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.y);
	}
	get yxzz(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.z);
	}
	get yyxx(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.x);
	}
	get yyxy(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.y);
	}
	get yyxz(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.z);
	}
	get yyyx(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.x);
	}
	get yyyy(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.y);
	}
	get yyyz(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.z);
	}
	get yyzx(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.x);
	}
	get yyzy(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.y);
	}
	get yyzz(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.z);
	}
	get yzxx(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.x);
	}
	get yzxy(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.y);
	}
	get yzxz(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.z);
	}
	get yzyx(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.x);
	}
	get yzyy(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.y);
	}
	get yzyz(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.z);
	}
	get yzzx(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.x);
	}
	get yzzy(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.y);
	}
	get yzzz(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.z);
	}
	get zxxx(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.x);
	}
	get zxxy(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.y);
	}
	get zxxz(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.z);
	}
	get zxyx(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.x);
	}
	get zxyy(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.y);
	}
	get zxyz(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.z);
	}
	get zxzx(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.x);
	}
	get zxzy(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.y);
	}
	get zxzz(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.z);
	}
	get zyxx(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.x);
	}
	get zyxy(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.y);
	}
	get zyxz(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.z);
	}
	get zyyx(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.x);
	}
	get zyyy(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.y);
	}
	get zyyz(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.z);
	}
	get zyzx(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.x);
	}
	get zyzy(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.y);
	}
	get zyzz(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.z);
	}
	get zzxx(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.x);
	}
	get zzxy(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.y);
	}
	get zzxz(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.z);
	}
	get zzyx(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.x);
	}
	get zzyy(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.y);
	}
	get zzyz(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.z);
	}
	get zzzx(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.x);
	}
	get zzzy(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.y);
	}
	get zzzz(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.z);
	}
}

export class Vec4 {
	constructor(readonly x: number, readonly y: number, readonly z: number, readonly w: number) {}
	add(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x + b, this.y + b, this.z + b, this.w + b) : new Vec4(this.x + b.x, this.y + b.y, this.z + b.z, this.w + b.w);
	}
	sub(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x - b, this.y - b, this.z - b, this.w - b) : new Vec4(this.x - b.x, this.y - b.y, this.z - b.z, this.w - b.w);
	}
	mul(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x * b, this.y * b, this.z * b, this.w * b) : new Vec4(this.x * b.x, this.y * b.y, this.z * b.z, this.w * b.w);
	}
	div(b: Vec4 | number): Vec4 {
		return typeof b === "number" ? new Vec4(this.x / b, this.y / b, this.z / b, this.w / b) : new Vec4(this.x / b.x, this.y / b.y, this.z / b.z, this.w / b.w);
	}
	neg(): Vec4 {
		return new Vec4(-this.x, -this.y, -this.z, -this.w);
	}
	get xx(): Vec2 {
		return new Vec2(this.x, this.x);
	}
	get xy(): Vec2 {
		return new Vec2(this.x, this.y);
	}
	get xz(): Vec2 {
		return new Vec2(this.x, this.z);
	}
	get xw(): Vec2 {
		return new Vec2(this.x, this.w);
	}
	get yx(): Vec2 {
		return new Vec2(this.y, this.x);
	}
	get yy(): Vec2 {
		return new Vec2(this.y, this.y);
	}
	get yz(): Vec2 {
		return new Vec2(this.y, this.z);
	}
	get yw(): Vec2 {
		return new Vec2(this.y, this.w);
	}
	get zx(): Vec2 {
		return new Vec2(this.z, this.x);
	}
	get zy(): Vec2 {
		return new Vec2(this.z, this.y);
	}
	get zz(): Vec2 {
		return new Vec2(this.z, this.z);
	}
	get zw(): Vec2 {
		return new Vec2(this.z, this.w);
	}
	get wx(): Vec2 {
		return new Vec2(this.w, this.x);
	}
	get wy(): Vec2 {
		return new Vec2(this.w, this.y);
	}
	get wz(): Vec2 {
		return new Vec2(this.w, this.z);
	}
	get ww(): Vec2 {
		return new Vec2(this.w, this.w);
	}
	get xxx(): Vec3 {
		return new Vec3(this.x, this.x, this.x);
	}
	get xxy(): Vec3 {
		return new Vec3(this.x, this.x, this.y);
	}
	get xxz(): Vec3 {
		return new Vec3(this.x, this.x, this.z);
	}
	get xxw(): Vec3 {
		return new Vec3(this.x, this.x, this.w);
	}
	get xyx(): Vec3 {
		return new Vec3(this.x, this.y, this.x);
	}
	get xyy(): Vec3 {
		return new Vec3(this.x, this.y, this.y);
	}
	get xyz(): Vec3 {
		return new Vec3(this.x, this.y, this.z);
	}
	get xyw(): Vec3 {
		return new Vec3(this.x, this.y, this.w);
	}
	get xzx(): Vec3 {
		return new Vec3(this.x, this.z, this.x);
	}
	get xzy(): Vec3 {
		return new Vec3(this.x, this.z, this.y);
	}
	get xzz(): Vec3 {
		return new Vec3(this.x, this.z, this.z);
	}
	get xzw(): Vec3 {
		return new Vec3(this.x, this.z, this.w);
	}
	get xwx(): Vec3 {
		return new Vec3(this.x, this.w, this.x);
	}
	get xwy(): Vec3 {
		return new Vec3(this.x, this.w, this.y);
	}
	get xwz(): Vec3 {
		return new Vec3(this.x, this.w, this.z);
	}
	get xww(): Vec3 {
		return new Vec3(this.x, this.w, this.w);
	}
	get yxx(): Vec3 {
		return new Vec3(this.y, this.x, this.x);
	}
	get yxy(): Vec3 {
		return new Vec3(this.y, this.x, this.y);
	}
	get yxz(): Vec3 {
		return new Vec3(this.y, this.x, this.z);
	}
	get yxw(): Vec3 {
		return new Vec3(this.y, this.x, this.w);
	}
	get yyx(): Vec3 {
		return new Vec3(this.y, this.y, this.x);
	}
	get yyy(): Vec3 {
		return new Vec3(this.y, this.y, this.y);
	}
	get yyz(): Vec3 {
		return new Vec3(this.y, this.y, this.z);
	}
	get yyw(): Vec3 {
		return new Vec3(this.y, this.y, this.w);
	}
	get yzx(): Vec3 {
		return new Vec3(this.y, this.z, this.x);
	}
	get yzy(): Vec3 {
		return new Vec3(this.y, this.z, this.y);
	}
	get yzz(): Vec3 {
		return new Vec3(this.y, this.z, this.z);
	}
	get yzw(): Vec3 {
		return new Vec3(this.y, this.z, this.w);
	}
	get ywx(): Vec3 {
		return new Vec3(this.y, this.w, this.x);
	}
	get ywy(): Vec3 {
		return new Vec3(this.y, this.w, this.y);
	}
	get ywz(): Vec3 {
		return new Vec3(this.y, this.w, this.z);
	}
	get yww(): Vec3 {
		return new Vec3(this.y, this.w, this.w);
	}
	get zxx(): Vec3 {
		return new Vec3(this.z, this.x, this.x);
	}
	get zxy(): Vec3 {
		return new Vec3(this.z, this.x, this.y);
	}
	get zxz(): Vec3 {
		return new Vec3(this.z, this.x, this.z);
	}
	get zxw(): Vec3 {
		return new Vec3(this.z, this.x, this.w);
	}
	get zyx(): Vec3 {
		return new Vec3(this.z, this.y, this.x);
	}
	get zyy(): Vec3 {
		return new Vec3(this.z, this.y, this.y);
	}
	get zyz(): Vec3 {
		return new Vec3(this.z, this.y, this.z);
	}
	get zyw(): Vec3 {
		return new Vec3(this.z, this.y, this.w);
	}
	get zzx(): Vec3 {
		return new Vec3(this.z, this.z, this.x);
	}
	get zzy(): Vec3 {
		return new Vec3(this.z, this.z, this.y);
	}
	get zzz(): Vec3 {
		return new Vec3(this.z, this.z, this.z);
	}
	get zzw(): Vec3 {
		return new Vec3(this.z, this.z, this.w);
	}
	get zwx(): Vec3 {
		return new Vec3(this.z, this.w, this.x);
	}
	get zwy(): Vec3 {
		return new Vec3(this.z, this.w, this.y);
	}
	get zwz(): Vec3 {
		return new Vec3(this.z, this.w, this.z);
	}
	get zww(): Vec3 {
		return new Vec3(this.z, this.w, this.w);
	}
	get wxx(): Vec3 {
		return new Vec3(this.w, this.x, this.x);
	}
	get wxy(): Vec3 {
		return new Vec3(this.w, this.x, this.y);
	}
	get wxz(): Vec3 {
		return new Vec3(this.w, this.x, this.z);
	}
	get wxw(): Vec3 {
		return new Vec3(this.w, this.x, this.w);
	}
	get wyx(): Vec3 {
		return new Vec3(this.w, this.y, this.x);
	}
	get wyy(): Vec3 {
		return new Vec3(this.w, this.y, this.y);
	}
	get wyz(): Vec3 {
		return new Vec3(this.w, this.y, this.z);
	}
	get wyw(): Vec3 {
		return new Vec3(this.w, this.y, this.w);
	}
	get wzx(): Vec3 {
		return new Vec3(this.w, this.z, this.x);
	}
	get wzy(): Vec3 {
		return new Vec3(this.w, this.z, this.y);
	}
	get wzz(): Vec3 {
		return new Vec3(this.w, this.z, this.z);
	}
	get wzw(): Vec3 {
		return new Vec3(this.w, this.z, this.w);
	}
	get wwx(): Vec3 {
		return new Vec3(this.w, this.w, this.x);
	}
	get wwy(): Vec3 {
		return new Vec3(this.w, this.w, this.y);
	}
	get wwz(): Vec3 {
		return new Vec3(this.w, this.w, this.z);
	}
	get www(): Vec3 {
		return new Vec3(this.w, this.w, this.w);
	}
	get xxxx(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.x);
	}
	get xxxy(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.y);
	}
	get xxxz(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.z);
	}
	get xxxw(): Vec4 {
		return new Vec4(this.x, this.x, this.x, this.w);
	}
	get xxyx(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.x);
	}
	get xxyy(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.y);
	}
	get xxyz(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.z);
	}
	get xxyw(): Vec4 {
		return new Vec4(this.x, this.x, this.y, this.w);
	}
	get xxzx(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.x);
	}
	get xxzy(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.y);
	}
	get xxzz(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.z);
	}
	get xxzw(): Vec4 {
		return new Vec4(this.x, this.x, this.z, this.w);
	}
	get xxwx(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.x);
	}
	get xxwy(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.y);
	}
	get xxwz(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.z);
	}
	get xxww(): Vec4 {
		return new Vec4(this.x, this.x, this.w, this.w);
	}
	get xyxx(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.x);
	}
	get xyxy(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.y);
	}
	get xyxz(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.z);
	}
	get xyxw(): Vec4 {
		return new Vec4(this.x, this.y, this.x, this.w);
	}
	get xyyx(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.x);
	}
	get xyyy(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.y);
	}
	get xyyz(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.z);
	}
	get xyyw(): Vec4 {
		return new Vec4(this.x, this.y, this.y, this.w);
	}
	get xyzx(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.x);
	}
	get xyzy(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.y);
	}
	get xyzz(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.z);
	}
	get xyzw(): Vec4 {
		return new Vec4(this.x, this.y, this.z, this.w);
	}
	get xywx(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.x);
	}
	get xywy(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.y);
	}
	get xywz(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.z);
	}
	get xyww(): Vec4 {
		return new Vec4(this.x, this.y, this.w, this.w);
	}
	get xzxx(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.x);
	}
	get xzxy(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.y);
	}
	get xzxz(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.z);
	}
	get xzxw(): Vec4 {
		return new Vec4(this.x, this.z, this.x, this.w);
	}
	get xzyx(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.x);
	}
	get xzyy(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.y);
	}
	get xzyz(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.z);
	}
	get xzyw(): Vec4 {
		return new Vec4(this.x, this.z, this.y, this.w);
	}
	get xzzx(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.x);
	}
	get xzzy(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.y);
	}
	get xzzz(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.z);
	}
	get xzzw(): Vec4 {
		return new Vec4(this.x, this.z, this.z, this.w);
	}
	get xzwx(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.x);
	}
	get xzwy(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.y);
	}
	get xzwz(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.z);
	}
	get xzww(): Vec4 {
		return new Vec4(this.x, this.z, this.w, this.w);
	}
	get xwxx(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.x);
	}
	get xwxy(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.y);
	}
	get xwxz(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.z);
	}
	get xwxw(): Vec4 {
		return new Vec4(this.x, this.w, this.x, this.w);
	}
	get xwyx(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.x);
	}
	get xwyy(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.y);
	}
	get xwyz(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.z);
	}
	get xwyw(): Vec4 {
		return new Vec4(this.x, this.w, this.y, this.w);
	}
	get xwzx(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.x);
	}
	get xwzy(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.y);
	}
	get xwzz(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.z);
	}
	get xwzw(): Vec4 {
		return new Vec4(this.x, this.w, this.z, this.w);
	}
	get xwwx(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.x);
	}
	get xwwy(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.y);
	}
	get xwwz(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.z);
	}
	get xwww(): Vec4 {
		return new Vec4(this.x, this.w, this.w, this.w);
	}
	get yxxx(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.x);
	}
	get yxxy(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.y);
	}
	get yxxz(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.z);
	}
	get yxxw(): Vec4 {
		return new Vec4(this.y, this.x, this.x, this.w);
	}
	get yxyx(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.x);
	}
	get yxyy(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.y);
	}
	get yxyz(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.z);
	}
	get yxyw(): Vec4 {
		return new Vec4(this.y, this.x, this.y, this.w);
	}
	get yxzx(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.x);
	}
	get yxzy(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.y);
	}
	get yxzz(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.z);
	}
	get yxzw(): Vec4 {
		return new Vec4(this.y, this.x, this.z, this.w);
	}
	get yxwx(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.x);
	}
	get yxwy(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.y);
	}
	get yxwz(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.z);
	}
	get yxww(): Vec4 {
		return new Vec4(this.y, this.x, this.w, this.w);
	}
	get yyxx(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.x);
	}
	get yyxy(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.y);
	}
	get yyxz(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.z);
	}
	get yyxw(): Vec4 {
		return new Vec4(this.y, this.y, this.x, this.w);
	}
	get yyyx(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.x);
	}
	get yyyy(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.y);
	}
	get yyyz(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.z);
	}
	get yyyw(): Vec4 {
		return new Vec4(this.y, this.y, this.y, this.w);
	}
	get yyzx(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.x);
	}
	get yyzy(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.y);
	}
	get yyzz(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.z);
	}
	get yyzw(): Vec4 {
		return new Vec4(this.y, this.y, this.z, this.w);
	}
	get yywx(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.x);
	}
	get yywy(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.y);
	}
	get yywz(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.z);
	}
	get yyww(): Vec4 {
		return new Vec4(this.y, this.y, this.w, this.w);
	}
	get yzxx(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.x);
	}
	get yzxy(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.y);
	}
	get yzxz(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.z);
	}
	get yzxw(): Vec4 {
		return new Vec4(this.y, this.z, this.x, this.w);
	}
	get yzyx(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.x);
	}
	get yzyy(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.y);
	}
	get yzyz(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.z);
	}
	get yzyw(): Vec4 {
		return new Vec4(this.y, this.z, this.y, this.w);
	}
	get yzzx(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.x);
	}
	get yzzy(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.y);
	}
	get yzzz(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.z);
	}
	get yzzw(): Vec4 {
		return new Vec4(this.y, this.z, this.z, this.w);
	}
	get yzwx(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.x);
	}
	get yzwy(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.y);
	}
	get yzwz(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.z);
	}
	get yzww(): Vec4 {
		return new Vec4(this.y, this.z, this.w, this.w);
	}
	get ywxx(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.x);
	}
	get ywxy(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.y);
	}
	get ywxz(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.z);
	}
	get ywxw(): Vec4 {
		return new Vec4(this.y, this.w, this.x, this.w);
	}
	get ywyx(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.x);
	}
	get ywyy(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.y);
	}
	get ywyz(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.z);
	}
	get ywyw(): Vec4 {
		return new Vec4(this.y, this.w, this.y, this.w);
	}
	get ywzx(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.x);
	}
	get ywzy(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.y);
	}
	get ywzz(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.z);
	}
	get ywzw(): Vec4 {
		return new Vec4(this.y, this.w, this.z, this.w);
	}
	get ywwx(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.x);
	}
	get ywwy(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.y);
	}
	get ywwz(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.z);
	}
	get ywww(): Vec4 {
		return new Vec4(this.y, this.w, this.w, this.w);
	}
	get zxxx(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.x);
	}
	get zxxy(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.y);
	}
	get zxxz(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.z);
	}
	get zxxw(): Vec4 {
		return new Vec4(this.z, this.x, this.x, this.w);
	}
	get zxyx(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.x);
	}
	get zxyy(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.y);
	}
	get zxyz(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.z);
	}
	get zxyw(): Vec4 {
		return new Vec4(this.z, this.x, this.y, this.w);
	}
	get zxzx(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.x);
	}
	get zxzy(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.y);
	}
	get zxzz(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.z);
	}
	get zxzw(): Vec4 {
		return new Vec4(this.z, this.x, this.z, this.w);
	}
	get zxwx(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.x);
	}
	get zxwy(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.y);
	}
	get zxwz(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.z);
	}
	get zxww(): Vec4 {
		return new Vec4(this.z, this.x, this.w, this.w);
	}
	get zyxx(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.x);
	}
	get zyxy(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.y);
	}
	get zyxz(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.z);
	}
	get zyxw(): Vec4 {
		return new Vec4(this.z, this.y, this.x, this.w);
	}
	get zyyx(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.x);
	}
	get zyyy(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.y);
	}
	get zyyz(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.z);
	}
	get zyyw(): Vec4 {
		return new Vec4(this.z, this.y, this.y, this.w);
	}
	get zyzx(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.x);
	}
	get zyzy(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.y);
	}
	get zyzz(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.z);
	}
	get zyzw(): Vec4 {
		return new Vec4(this.z, this.y, this.z, this.w);
	}
	get zywx(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.x);
	}
	get zywy(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.y);
	}
	get zywz(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.z);
	}
	get zyww(): Vec4 {
		return new Vec4(this.z, this.y, this.w, this.w);
	}
	get zzxx(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.x);
	}
	get zzxy(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.y);
	}
	get zzxz(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.z);
	}
	get zzxw(): Vec4 {
		return new Vec4(this.z, this.z, this.x, this.w);
	}
	get zzyx(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.x);
	}
	get zzyy(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.y);
	}
	get zzyz(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.z);
	}
	get zzyw(): Vec4 {
		return new Vec4(this.z, this.z, this.y, this.w);
	}
	get zzzx(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.x);
	}
	get zzzy(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.y);
	}
	get zzzz(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.z);
	}
	get zzzw(): Vec4 {
		return new Vec4(this.z, this.z, this.z, this.w);
	}
	get zzwx(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.x);
	}
	get zzwy(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.y);
	}
	get zzwz(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.z);
	}
	get zzww(): Vec4 {
		return new Vec4(this.z, this.z, this.w, this.w);
	}
	get zwxx(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.x);
	}
	get zwxy(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.y);
	}
	get zwxz(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.z);
	}
	get zwxw(): Vec4 {
		return new Vec4(this.z, this.w, this.x, this.w);
	}
	get zwyx(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.x);
	}
	get zwyy(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.y);
	}
	get zwyz(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.z);
	}
	get zwyw(): Vec4 {
		return new Vec4(this.z, this.w, this.y, this.w);
	}
	get zwzx(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.x);
	}
	get zwzy(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.y);
	}
	get zwzz(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.z);
	}
	get zwzw(): Vec4 {
		return new Vec4(this.z, this.w, this.z, this.w);
	}
	get zwwx(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.x);
	}
	get zwwy(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.y);
	}
	get zwwz(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.z);
	}
	get zwww(): Vec4 {
		return new Vec4(this.z, this.w, this.w, this.w);
	}
	get wxxx(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.x);
	}
	get wxxy(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.y);
	}
	get wxxz(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.z);
	}
	get wxxw(): Vec4 {
		return new Vec4(this.w, this.x, this.x, this.w);
	}
	get wxyx(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.x);
	}
	get wxyy(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.y);
	}
	get wxyz(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.z);
	}
	get wxyw(): Vec4 {
		return new Vec4(this.w, this.x, this.y, this.w);
	}
	get wxzx(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.x);
	}
	get wxzy(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.y);
	}
	get wxzz(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.z);
	}
	get wxzw(): Vec4 {
		return new Vec4(this.w, this.x, this.z, this.w);
	}
	get wxwx(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.x);
	}
	get wxwy(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.y);
	}
	get wxwz(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.z);
	}
	get wxww(): Vec4 {
		return new Vec4(this.w, this.x, this.w, this.w);
	}
	get wyxx(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.x);
	}
	get wyxy(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.y);
	}
	get wyxz(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.z);
	}
	get wyxw(): Vec4 {
		return new Vec4(this.w, this.y, this.x, this.w);
	}
	get wyyx(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.x);
	}
	get wyyy(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.y);
	}
	get wyyz(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.z);
	}
	get wyyw(): Vec4 {
		return new Vec4(this.w, this.y, this.y, this.w);
	}
	get wyzx(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.x);
	}
	get wyzy(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.y);
	}
	get wyzz(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.z);
	}
	get wyzw(): Vec4 {
		return new Vec4(this.w, this.y, this.z, this.w);
	}
	get wywx(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.x);
	}
	get wywy(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.y);
	}
	get wywz(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.z);
	}
	get wyww(): Vec4 {
		return new Vec4(this.w, this.y, this.w, this.w);
	}
	get wzxx(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.x);
	}
	get wzxy(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.y);
	}
	get wzxz(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.z);
	}
	get wzxw(): Vec4 {
		return new Vec4(this.w, this.z, this.x, this.w);
	}
	get wzyx(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.x);
	}
	get wzyy(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.y);
	}
	get wzyz(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.z);
	}
	get wzyw(): Vec4 {
		return new Vec4(this.w, this.z, this.y, this.w);
	}
	get wzzx(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.x);
	}
	get wzzy(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.y);
	}
	get wzzz(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.z);
	}
	get wzzw(): Vec4 {
		return new Vec4(this.w, this.z, this.z, this.w);
	}
	get wzwx(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.x);
	}
	get wzwy(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.y);
	}
	get wzwz(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.z);
	}
	get wzww(): Vec4 {
		return new Vec4(this.w, this.z, this.w, this.w);
	}
	get wwxx(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.x);
	}
	get wwxy(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.y);
	}
	get wwxz(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.z);
	}
	get wwxw(): Vec4 {
		return new Vec4(this.w, this.w, this.x, this.w);
	}
	get wwyx(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.x);
	}
	get wwyy(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.y);
	}
	get wwyz(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.z);
	}
	get wwyw(): Vec4 {
		return new Vec4(this.w, this.w, this.y, this.w);
	}
	get wwzx(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.x);
	}
	get wwzy(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.y);
	}
	get wwzz(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.z);
	}
	get wwzw(): Vec4 {
		return new Vec4(this.w, this.w, this.z, this.w);
	}
	get wwwx(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.x);
	}
	get wwwy(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.y);
	}
	get wwwz(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.z);
	}
	get wwww(): Vec4 {
		return new Vec4(this.w, this.w, this.w, this.w);
	}
}

export class Mat4 {
	constructor(readonly c0: Vec4, readonly c1: Vec4, readonly c2: Vec4, readonly c3: Vec4) {}
	mul(b: Mat4): Mat4;
	mul(b: Vec4): Vec4;
	mul(b: Mat4 | Vec4): Mat4 | Vec4 {
		if (b instanceof Vec4) return this.c0.mul(b.x).add(this.c1.mul(b.y)).add(this.c2.mul(b.z)).add(this.c3.mul(b.w));
		return new Mat4(this.mul(b.c0), this.mul(b.c1), this.mul(b.c2), this.mul(b.c3));
	}
}

// a rotation as a unit quaternion (helder.math.Quat: x, y, z the
// vector part, w the scalar one), an immutable value; a.mul(b) rotates by
// b first, then by a; angles in radians, right-handed (as Mat4's)
export class Quat {
	constructor(readonly x: number, readonly y: number, readonly z: number, readonly w: number) {}
	static identity(): Quat {
		return new Quat(0, 0, 0, 1);
	}
	// a turn by angle about axis (of any length but zero)
	static axisAngle(axis: Vec3, angle: number): Quat {
		const l = Math.sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z);
		const s = Math.sin(angle / 2) / l;
		return new Quat(axis.x * s, axis.y * s, axis.z * s, Math.cos(angle / 2));
	}
	// the turns about x, then y, then z
	static fromEuler(x: number, y: number, z: number): Quat {
		return Quat.axisAngle(new Vec3(0, 0, 1), z).mul(Quat.axisAngle(new Vec3(0, 1, 0), y)).mul(Quat.axisAngle(new Vec3(1, 0, 0), x));
	}
	mul(b: Quat): Quat {
		const a = this;
		return new Quat(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
			a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z);
	}
}
