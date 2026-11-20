package helder.asset;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

class StringsMacro {
	public static function make(path:String):Expr {
		var pos = Context.currentPos(), root = AssetMacro.root(), folder = AssetMacro.find(path, "strings", true);
		var project = try StringFiles.read(path, folder, root, message -> Context.warning(message, pos))
			catch (e:Dynamic) Context.error('Asset.strings("$path"): $e', pos);
		var module = Context.getLocalModule(), config = haxe.io.Path.join([root, "helder.json"]);
		Context.registerModuleDependency(module, folder);
		if (sys.FileSystem.exists(config)) Context.registerModuleDependency(module, config);
		var sources = [for (entry in project.files) {
			Context.registerModuleDependency(module, entry.file);
			AssetMacro.bundle(entry.key, entry.file, true);
			macro {tag: $v{entry.tag}, key: $v{Bundle.MARK + "now:" + entry.key + "\x01"}, file: $v{AssetMacro.devPath(entry.file)}};
		}];
		var keys = [for (key in project.messages.keys()) key];
		keys.sort(Reflect.compare);
		var tree = new MessageFields();
		for (key in keys) {
			var params = project.messages.get(key).params, fields:Array<Field> = [];
			for (name in params.keys()) fields.push({
				name: name,
				pos: pos,
				kind: FVar(params.get(name) ? macro:Float : macro:String)
			});
			var value = fields.length == 0 ? macro () -> messages.get($v{key}) : {
				pos: pos,
				expr: EFunction(FArrow, {
					args: [{name: "params", type: TAnonymous(fields)}],
					ret: macro:String,
					expr: macro return messages.get($v{key}, params)
				})
			};
			try tree.add(key.split("."), 0, value) catch (e:Dynamic) Context.error('Asset.strings("$path"): "$key": $e', pos);
		}
		return macro {
			var messages = new helder.asset.Strings($v{project.fallback}, $a{sources});
			${tree.expression(pos)};
		};
	}
}

private class MessageFields {
	final children = new Map<String, MessageFields>();
	var leaf:Null<Expr>;

	public function new() {}

	public function add(path:Array<String>, at:Int, value:Expr) {
		if (leaf != null || (at == path.length && children.keys().hasNext())) throw "a key is also a namespace";
		if (at == path.length) {
			leaf = value;
			return;
		}
		var name = path[at];
		if (!~/^[a-zA-Z_][a-zA-Z_0-9]*$/.match(name)) throw 'invalid field "$name"';
		var child = children.get(name);
		if (child == null) children.set(name, child = new MessageFields());
		child.add(path, at + 1, value);
	}

	public function expression(pos:Position):Expr
		return leaf ?? {pos: pos, expr: EObjectDecl([for (name => child in children) {field: name, expr: child.expression(pos)}])};
}
#end
