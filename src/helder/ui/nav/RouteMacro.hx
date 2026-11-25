package helder.ui.nav;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// Routes.route's typing: the path, a literal, read for its params, render
// typed as a function of a structure of them (each a String) and given
// their values in order (helder.ui.nav.Router.add)
class RouteMacro {
	public static function route(self:Expr, path:Expr, render:Expr):Expr {
		var text = switch path.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("Routes.route: the path is a literal (its params are typed from it)", path.pos);
		}
		var names = [];
		for (p in text.split("/")) {
			if (p.indexOf("*") >= 0 || p.indexOf("?") >= 0) Context.error('Routes.route: no optional segments or wildcards ($p)', path.pos);
			if (p.charAt(0) != ":") continue;
			var n = p.substr(1);
			if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(n)) Context.error('Routes.route: $p is no param name', path.pos);
			if (names.indexOf(n) >= 0) Context.error('Routes.route: $n twice', path.pos);
			names.push(n);
		}
		var params:ComplexType = TAnonymous([for (n in names) {name: n, kind: FVar(macro :String), pos: path.pos}]);
		var fields = [for (i => n in names) {field: n, expr: macro values[$v{i}]}];
		var record = {expr: EObjectDecl(fields), pos: path.pos};
		return macro @:pos(render.pos) {
			var router:helder.ui.nav.Router = $self;
			var render:$params->helder.view.View = $render;
			(router.add($path, values -> render($record)) : helder.ui.nav.Routes);
		};
	}
}
#end
