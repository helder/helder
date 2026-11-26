package helder.scenario;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// A scenario file's scenarios (Foo.scenario.hx linked as Foo_scenario, as
// story files are): its module-level values made by scenario({...}), in
// the order written
class Scenarios {
	public static macro function of(module:String):Expr {
		var out = [];
		for (t in Context.getModule(module))
			switch t {
				case TInst(_.get() => c, _) if (c.kind.match(KModuleFields(_))):
					var fields = c.statics.get().filter(f -> switch haxe.macro.TypeTools.followWithAbstracts(f.type) {
						case TInst(_.get() => {pack: ["helder", "scenario"], name: "Scenario"}, _): true;
						case _: false;
					});
					fields.sort((a, b) -> Context.getPosInfos(a.pos).min - Context.getPosInfos(b.pos).min);
					for (f in fields)
						out.push(macro $p{module.split(".").concat([f.name])});
				case _:
			}
		return macro([$a{out}] : Array<helder.scenario.Scenario>);
	}
}
