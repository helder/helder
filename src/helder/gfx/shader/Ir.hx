package helder.gfx.shader;

// The shader IR: what a shader definition's adapter (Lower, Haxe's typed
// functions; helder.typescript's, TypeScript's) makes of its stages and
// the functions they call, the handler (ShaderDefinition) checks and the
// emitters (Glsl, Wgsl, Msl, Hlsl) print. The kernel of definitions
// (helder.compiler.Kernel) for shaders. Typed
// and structured (no gotos): values of scalar, vector, matrix and struct
// types, locals assigned in statements, calls to functions that are not
// recursive. Names are already the emitted ones (Names avoids every
// language's keywords and builtins), so an emitter only prints.

enum SType {
	TVoid;
	TBool;
	TInt;
	TFloat;
	TVec(n:Int); // 2 to 4 floats
	TMat4; // 4 columns of vec4
	TTexture; // a Texture2D: a texture and its sampler (parameters only)
	TTextureCube; // a TextureCube: a cube texture and its sampler (parameters only)
	TTextureArray; // a Texture2DArray: a 2D array texture and its sampler (parameters only)
	TStruct(s:SStruct);
	// n of them: a uniform block's field (Vec4s or Mat4s: std140's stride is theirs), read by index
	TArray(t:SType, n:Int);
	// a storage buffer of elements of t (a compute stage's parameter only:
	// Storage, write false; RWStorage, write true), read by index, written by SStore
	TStorage(t:SType, write:Bool);
	// a storage texture, write only (a compute stage's parameter only), of a
	// TextureFormat (its value: RGBA8, RGBA16F, R32F)
	TImage(format:Int);
	// an array of workgroup memory of elements of t (a compute stage's
	// third parameter's field, Workgroup<T>: SShared), read by index,
	// written by SStore
	TWorkgroup(t:SType);
}

class SStruct {
	public final name:String;
	public final fields:Array<SField>;
	// the Haxe class (path), for errors and the CPU writers
	public final path:String;

	public function new(name, path, fields) {
		this.name = name;
		this.path = path;
		this.fields = fields;
	}
}

typedef SField = {
	name:String, // emitted
	field:String, // Haxe's
	type:SType,
	// the clip-space position of a vertex stage's output (built position(...))
	position:Bool,
	// (an optional field, ?tangent: a variant drops it where it is never read)
	?optional:Bool
}

class SVar {
	public var name:String;
	public final type:SType;
	// assigned after its declaration (WGSL: var, else let; a parameter: copied)
	public var assigned = false;
	// (a stage's parameter from an optional field of its parameters: a variant drops it where it is never read)
	public var optional = false;

	public function new(name, type) {
		this.name = name;
		this.type = type;
	}
}

typedef SExpr = {e:SExprDef, t:SType};

enum SExprDef {
	EFloat(f:Float);
	EInt(i:Int);
	EBool(b:Bool);
	ELocal(v:SVar);
	EField(e:SExpr, name:String); // of a struct
	ESwizzle(e:SExpr, comps:String); // of a vector: x, y, z, w
	EColumn(e:SExpr, i:Int); // of a matrix
	EIndex(e:SExpr, i:SExpr); // of an array, an Int
	EUnop(op:SUnop, e:SExpr);
	EBinop(op:SBinop, a:SExpr, b:SExpr); // scalars, componentwise, matrix products
	ECond(c:SExpr, a:SExpr, b:SExpr);
	// a value of type t from its parts: a vector's components (or vectors,
	// or one scalar for all), a matrix's columns, a struct's fields
	ENew(args:Array<SExpr>);
	EBuiltin(name:String, args:Array<SExpr>); // GLSL's name (ShaderMath)
	ECall(f:SFunction, args:Array<SExpr>);
	EConvert(e:SExpr); // a scalar to t (Int, Float)
}

enum SUnop {
	Neg;
	Not;
	BitNot;
}

enum SBinop {
	Add;
	Sub;
	Mul;
	Div;
	Mod;
	Eq;
	Ne;
	Lt;
	Le;
	Gt;
	Ge;
	And;
	Or;
	BitAnd;
	BitOr;
	BitXor;
	Shl;
	Shr;
}

enum SStmt {
	SDecl(v:SVar, init:Null<SExpr>);
	SAssign(v:SVar, op:Null<SBinop>, e:SExpr);
	SEval(e:SExpr); // a call
	SIf(c:SExpr, a:Array<SStmt>, b:Null<Array<SStmt>>);
	SWhile(c:SExpr, body:Array<SStmt>);
	SBreak;
	SContinue;
	SReturn(e:Null<SExpr>);
	// b[i] = v, b a storage buffer written (TStorage(_, true))
	SStore(b:SExpr, i:SExpr, v:SExpr);
}

class SFunction {
	public final name:String;
	public final params:Array<SVar>;
	public var ret:SType; // (TypeScript: known after the body when not written)
	public var body:Array<SStmt> = [];
	// (a stage's: the fields of its object of parameters, as written, one a
	// parameter after the input each: params[i + 1])
	public var fields:Array<String> = [];
	// (a compute stage's: the fields of its object of workgroup memory, its
	// third parameter, the parameters after those of fields; length 0: the
	// workgroup's)
	public var workgroup:Array<{name:String, length:Int}> = [];

	public function new(name, params, ret) {
		this.name = name;
		this.params = params;
		this.ret = ret;
	}
}

// a uniform block: a struct parameter of an entry point after its input,
// at a binding (its slot) shared by both stages (std140 offsets: the same in WGSL for
// these types; MSL and HLSL declare them explicitly)
class SUniform {
	public final struct:SStruct;
	public final binding:Int;
	public final offsets:Array<Int>;
	public final size:Int;

	public function new(struct, binding, offsets, size) {
		this.struct = struct;
		this.binding = binding;
		this.offsets = offsets;
		this.size = size;
	}
}

// a texture parameter of an entry point after its input (Texture2D,
// TextureCube, Texture2DArray: dimension 0, 1, 2), by its name, at a slot
// shared by both stages
class STexture {
	public final name:String;
	public final slot:Int;
	public final dimension:Int;

	public function new(name, slot, dimension = 0) {
		this.name = name;
		this.slot = slot;
		this.dimension = dimension;
	}
}

class Textures {
	// whether t is a texture parameter's type (2D, cube or array; null: none)
	public static function isTexture(t:Null<SType>):Bool
		return t != null && switch t {
			case TTexture | TTextureCube | TTextureArray: true;
			case _: false;
		}

	// a texture type's dimension (STexture's), -1 for any other type
	public static function dimension(t:SType):Int
		return switch t {
			case TTexture: 0;
			case TTextureCube: 1;
			case TTextureArray: 2;
			case _: -1;
		}
}

// a storage buffer parameter of a compute stage, by its name, at a slot;
// its elements' std430 layout (a struct's offsets, the stride); index: its
// place among the stage's storage buffers (GL's binding) or, written, among
// the buffers and textures it writes (HLSL's u register: a UAV)
class SStorage {
	public final name:String;
	public final slot:Int;
	public final element:SType;
	public final write:Bool;
	public final offsets:Array<Int>;
	public final stride:Int;
	public final index:Int;

	public function new(name, slot, element, write, offsets, stride, index) {
		this.name = name;
		this.slot = slot;
		this.element = element;
		this.write = write;
		this.offsets = offsets;
		this.stride = stride;
		this.index = index;
	}
}

// a storage texture parameter of a compute stage: its TextureFormat; index:
// its place among the stage's storage textures (GL's image unit) and among
// what it writes (HLSL's u register), apart
class SImage {
	public final name:String;
	public final slot:Int;
	public final format:Int;
	public final index:Int;
	public final uav:Int;

	public function new(name, slot, format, index, uav) {
		this.name = name;
		this.slot = slot;
		this.format = format;
		this.index = index;
		this.uav = uav;
	}
}

// an entry point's parameter after its input
enum SResource {
	RUniform(u:SUniform);
	RTexture(t:STexture);
	RStorage(s:SStorage);
	RImage(i:SImage);
}

enum abstract SStage(Int) {
	var Vertex;
	var Fragment;
	var Compute;
}

// one stage: its function (input, then resources), what it needs in
// declaration order (structs, then functions, callees first)
class SEntry {
	public final stage:SStage;
	public final fn:SFunction;
	public final input:SStruct;
	public final resources:Array<SResource>;
	public final uniforms:Array<SUniform>;
	public final textures:Array<STexture>;
	public final structs:Array<SStruct>;
	public final functions:Array<SFunction>;

	public function new(stage, fn, input, resources:Array<SResource>, structs, functions) {
		this.stage = stage;
		this.fn = fn;
		this.input = input;
		this.resources = resources;
		uniforms = [for (r in resources) switch r {
			case RUniform(u): u;
			case _: continue;
		}];
		textures = [for (r in resources) switch r {
			case RTexture(t): t;
			case _: continue;
		}];
		this.structs = structs;
		this.functions = functions;
	}
}

// an array of a compute stage's workgroup memory: a field of its third
// parameter (Workgroup<T>), or a subgroup operation's scratch where they are
// emulated (Subgroups), its parameter in the stage's function (v: after
// the resources, in order), its elements' type and layout (std430, as WGSL
// counts its bytes) and its length; emitted wg_<index>
class SShared {
	public final name:String;
	public final v:SVar;
	public final element:SType;
	public final length:Int;
	// (std430: a struct's fields' offsets, an element's bytes)
	public final offsets:Array<Int>;
	public final stride:Int;
	public final index:Int;

	public function new(name, v, element, length, offsets, stride, index) {
		this.name = name;
		this.v = v;
		this.element = element;
		this.length = length;
		this.offsets = offsets;
		this.stride = stride;
		this.index = index;
	}

	// the bytes it takes
	public var bytes(get, never):Int;

	inline function get_bytes()
		return stride * length;
}

// a compute stage (compute({size, main})): its entry, its workgroup's size
// (x, y, z), its resources by kind and its workgroup memory; subgroups:
// it uses them (an operation or one of ComputeInput's subgroup fields);
// emulated: they are made of workgroup memory and barriers here, in
// subgroups of 4 (Subgroups.emulate), else the language's own
class SCompute {
	public final entry:SEntry;
	public final size:Array<Int>;
	public final storage:Array<SStorage>;
	public final images:Array<SImage>;
	public final shared:Array<SShared>;
	public final subgroups:Bool;
	public final emulated:Bool;

	public function new(entry, size, shared, subgroups = false, emulated = false) {
		this.entry = entry;
		this.size = size;
		this.shared = shared;
		this.subgroups = subgroups;
		this.emulated = emulated;
		storage = [for (r in entry.resources) switch r {
			case RStorage(s): s;
			case _: continue;
		}];
		images = [for (r in entry.resources) switch r {
			case RImage(i): i;
			case _: continue;
		}];
	}

	// the invocations of a workgroup
	public var invocations(get, never):Int;

	inline function get_invocations()
		return size[0] * size[1] * size[2];
}

class SProgram {
	public final vertex:SEntry;
	public final fragment:SEntry;
	public final uniforms:Array<SUniform>;
	public final textures:Array<STexture>;

	public function new(vertex, fragment, uniforms, textures) {
		this.vertex = vertex;
		this.fragment = fragment;
		this.uniforms = uniforms;
		this.textures = textures;
	}

	// the vertex stage's output (the varyings): the fragment stage's input
	public var varyings(get, never):SStruct;

	inline function get_varyings()
		return fragment.input;
}
