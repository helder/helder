package helder.typescript.js;

// A TypeScript position in hxmc's table of lines (Stmt.SPos, which the
// frames of a stack are named from: hxmc.StackTable): its line and its
// UTF-16 column in one number, as the table has lines only. -debug's DWARF
// lines are these numbers too.
class Lines {
	public static inline function pack(line:Int, column:Int):Int
		return (line < 1 << 19 ? line : (1 << 19) - 1) << 12 | (column < 4096 ? column : 4095);

	public static inline function line(p:Int):Int
		return p >>> 12;

	public static inline function column(p:Int):Int
		return p & 4095;

	// whether a frame's file is a program's (its lines packed)
	public static function typescript(file:Null<String>):Bool
		return file != null && (StringTools.endsWith(file, ".ts") || StringTools.endsWith(file, ".tsx") || StringTools.endsWith(file, ".mts")
			|| StringTools.endsWith(file, ".cts"));
}
