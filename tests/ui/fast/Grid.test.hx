package ui.fast;

import helder.test.Test;
import helder.ui.fast.FastTags.*;
import helder.ui.fast.GridTerms;
import helder.view.*;
import helder.view.graph.Graph.*;

// Grid layout on fast nodes: CSS's grid values read as the cascade
// computes them, laid out by the engine's GridFlow.
function tests() {
	describe("grid", () -> {
		test("CSS's values read as the cascade computes them", () -> {
			equals(Std.string(GridTerms.tracks("1fr 200px 30%")), "[Dimension(1,fr),Dimension(200,px),Percentage(30)]");
			equals(Std.string(GridTerms.tracks("repeat(3, 1fr)")), "[Func(repeat,[Number(3,true),Delim(,),Dimension(1,fr)])]");
			equals(Std.string(GridTerms.tracks("[a] minmax(100px, 1fr) [b] auto")),
				"[Brackets([,[Ident(a)]),Func(minmax,[Dimension(100,px),Delim(,),Dimension(1,fr)]),Brackets([,[Ident(b)]),Keyword(auto)]");
			equals(Std.string(GridTerms.tracks("auto 1fr min-content fit-content(200px)")),
				"[Keyword(auto),Dimension(1,fr),Keyword(min-content),Func(fit-content,[Dimension(200,px)])]");
			equals(Std.string(GridTerms.flow("row dense")), "[Keyword(dense)]");
			equals(Std.string(GridTerms.lines("1 / 3")), "[[Number(1,true)],[Number(3,true)]]");
			equals(Std.string(GridTerms.lines("span 2")), "[[Keyword(span),Number(2,true)],[Keyword(auto)]]");
			equals(Std.string(GridTerms.lines("head")), "[[Ident(head)],[Ident(head)]]");
			equals(Std.string(GridTerms.areas("'head head' 'side main'")), "[Str(head head),Str(side main)]");
		});
		test("a grid in markup: its tracks, areas and an item's lines", () -> {
			var ui = new helder.ui.Ui(null, 400, 300), tree:Null<helder.ui.fast.Tree> = null;
			Render.render(<Fast ref={t -> tree = t}>
				<view display="grid" width={300} gridTemplateColumns="100px 1fr" gridTemplateRows="40px 60px" gridTemplateAreas="'head head' 'side main'" columnGap={10}>
					<view tag="head" gridArea="head"/>
					<view tag="side" gridArea="side"/>
					<view tag="main" gridArea="main"/>
					<view tag="wide" gridColumn="1 / 3" height={20}/>
				</view>
			</Fast>, ui.root);
			flush();
			ui.update();
			var g = tree.root.children()[0], r = (tag:String) -> tree.rectOf(g.children().filter(c -> c.tag == tag)[0]).join(",");
			equals(r("head"), "0,0,300,40");
			equals(r("side"), "0,40,100,60");
			equals(r("main"), "110,40,190,60");
			// (an implicit row after the template's: its own content's height)
			equals(r("wide"), "0,100,300,20");
		});
	});
}
