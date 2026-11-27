// (a file's text in the program, read when it is compiled: "" where there is none yet)
class Embed {
	public static macro function text(path:String):haxe.macro.Expr
		return macro $v{sys.FileSystem.exists(path) ? sys.io.File.getContent(path) : ""};
}
