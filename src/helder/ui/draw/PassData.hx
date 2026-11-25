package helder.ui.draw;

import helder.ui.draw.FrameStreams.FrameInput;

// What a node drawn on the GPU draws, as data a frame keeps in its place
// (FrameWriter.data: a markup <Scene>'s tags and props, helder.scene.view's
// SceneData), drawn again from it where the frame is shown (a studio's
// still: crisp at any zoom). A tree of elements: a tag, named values
// (numbers, vectors, texts, flags), children. Written into a frame's
// streams, its numbers as floats: a loop's frames step only those that
// changed (FrameLoop).
class PassData {
	// (FrameReader's marker: a GPU texture of this id less the data's index, a pass's place in the list)
	public static inline var MARK = -1000000;

	public final kind:String;
	public final root:PassElement;

	public function new(kind:String, root:PassElement) {
		this.kind = kind;
		this.root = root;
	}

	public function write(o:FrameStreams) {
		o.string(kind);
		element(o, root, 0);
	}

	static function element(o:FrameStreams, e:PassElement, depth:Int) {
		o.string(e.tag);
		o.uint(e.names.length);
		for (k => name in e.names) {
			o.string(name);
			switch e.values[k] {
				case Num(v):
					o.uint(0);
					o.float(100 + (k & 15), v);
				case Vec(a):
					o.uint(a.length);
					for (j => v in a)
						o.float(120 + j, v);
				case Text(s):
					o.uint(8);
					o.string(s);
				case Flag(b):
					o.uint(b ? 9 : 10);
			}
		}
		o.uint(e.children.length);
		for (c in e.children)
			element(o, c, depth + 1);
	}

	public static function read(r:FrameInput):PassData {
		var kind = r.string();
		return new PassData(kind, readElement(r));
	}

	static function readElement(r:FrameInput):PassElement {
		var e = new PassElement(r.string());
		for (k in 0...Std.int(r.uint())) {
			e.names.push(r.string());
			e.values.push(switch Std.int(r.uint()) {
				case 0: Num(r.float(100 + (k & 15)));
				case 8: Text(r.string());
				case 9: Flag(true);
				case 10: Flag(false);
				case n: Vec([for (j in 0...n) r.float(120 + j)]);
			});
		}
		for (_ in 0...Std.int(r.uint()))
			e.children.push(readElement(r));
		return e;
	}
}

// (an element: its tag, its values by name, its children)
class PassElement {
	public final tag:String;
	public final names:Array<String> = [];
	public final values:Array<PassValue> = [];
	public final children:Array<PassElement> = [];

	public function new(tag:String)
		this.tag = tag;

	public function set(name:String, v:PassValue):PassElement {
		names.push(name);
		values.push(v);
		return this;
	}

	public function get(name:String):Null<PassValue> {
		var k = names.indexOf(name);
		return k < 0 ? null : values[k];
	}
}

enum PassValue {
	Num(v:Float);
	// (2 to 4 numbers: a Vec2, Vec3, Vec4; a Quat: its x, y, z, w)
	Vec(a:Array<Float>);
	Text(s:String);
	Flag(b:Bool);
}
