package helder.ui;

import haxe.macro.Expr;
import helder.view.View;
import helder.view.graph.Read;

// Screens by path, shown by a Stack (helder.ui.nav.Router's, which
// TypeScript's is): route's params are typed by its path, a literal
// ("/product/:id": {id:String}).
//   final nav = new Router()
//     .route("/", _ -> <Home/>)
//     .route("/product/:id", p -> <Product id={p.id}/>)
//     .fallback(path -> <NotFound path={path}/>);
@:forward(go, back, backTo, replace, reset, open, path, depth)
abstract Router(helder.ui.nav.Router) from helder.ui.nav.Router to helder.ui.nav.Router {
	public inline function new()
		this = new helder.ui.nav.Router();

	public macro function route(self:Expr, path:ExprOf<String>, render:Expr):ExprOf<Router>
		return helder.ui.nav.RouteMacro.route(self, path, render);

	public inline function fallback(render:String->View):Router
		return this.fallback(render);

	// the top's query
	public var query(get, never):Read<Map<String, String>>;

	inline function get_query():Read<Map<String, String>>
		return this.queries;
}
