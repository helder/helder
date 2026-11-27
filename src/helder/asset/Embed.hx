package helder.asset;

#if macro
import haxe.macro.Expr;
#end

// A file's bytes built into the code itself: no bundle, nothing to load
// (PackedModel.read(Embed.bytes("level.hxm3d"), device)). For small files,
// read when compiling and not reloaded. Only haxe.crypto.Base64.decode is
// generated, so a program that embeds a font links nothing of Asset, whose
// loads are helder.async's (tests/web/links.mjs).
class Embed {
	@:definition public static macro function bytes(path:Expr):Expr
		return AssetDefinition.forward("embed", path);
}
