package helder.ui.flow;

import haxe.ds.ObjectMap;
import helder.ui.box.Box;
import helder.ui.flow.Fragmentation.Resume;

// Where layout resumes in the next fragmentainer (LayoutNG's break
// token): each box on the way from the root to the break and where it
// goes on, at a child or a line. Boxes, never fragments: a fragmentainer's
// fragments can be painted and dropped, the token kept.
class BreakToken {
	// (a Resume's line past its box's content: only its height left)
	public static inline var PAST = -2;

	public final resumes:ObjectMap<Box, Resume>;
	// a forced break's page side ("left", "right": the next page is that side, a blank one between if not)
	public final side:Null<String>;
	// the next page's name (the page property of what it starts with; null: none)
	public final name:Null<String>;

	public function new(resumes:ObjectMap<Box, Resume>, side:Null<String>, name:Null<String>) {
		this.resumes = resumes;
		this.side = side;
		this.name = name;
	}
}
