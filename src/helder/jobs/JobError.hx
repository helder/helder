package helder.jobs;

import haxe.CallStack;

// A job's failure, thrown in the awaiting task: a GC-free job's code (its
// result < 0), or a GC job's exception (code -1, its message; the
// exception itself stays on the thread or in the worker that threw it, its
// stack comes back as the previous exception's: where it was thrown).
class JobError extends haxe.Exception {
	public final code:Int;

	public function new(code:Int, ?message:String, ?previous:haxe.Exception) {
		super(message ?? 'job failed: $code', previous);
		this.code = code;
	}

	// (a GC job's: its stack's lines, `name\tfile\tline` each)
	@:noCompletion public static function of(code:Int, message:Null<String>, where:Null<String>):JobError {
		if (where == null || where == "") return new JobError(code, message);
		var thrown = new haxe.Exception(message ?? 'job failed: $code');
		#if (target.name == "hxmc")
		thrown.stack = [
			for (l in where.split("\n")) {
				var p = l.split("\t");
				FilePos(item(p[0]), p[1], Std.parseInt(p[2]) ?? 0);
			}
		];
		#end
		return new JobError(code, message, thrown);
	}

	@:noCompletion public static function lines(stack:CallStack):String
		return [
			for (i in stack)
				switch i {
					case FilePos(s, file, line, _): name(s) + "\t" + file + "\t" + line;
					case _: continue;
				}
		].join("\n");

	static function name(s:Null<StackItem>):String
		return switch s {
			case Method(c, m): (c ?? "") + "." + m;
			case LocalFunction(n): "#" + n;
			case Module(m): m;
			case _: "";
		}

	static function item(name:String):StackItem {
		if (StringTools.startsWith(name, "#")) return LocalFunction(Std.parseInt(name.substr(1)) ?? 0);
		var dot = name.lastIndexOf(".");
		return dot < 0 ? Module(name) : Method(name.substr(0, dot), name.substr(dot + 1));
	}
}
