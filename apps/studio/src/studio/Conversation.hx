package studio;

import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import studio.Turn;

// The chat's state (the watched shell's: Chat): the turns so far, the one
// running last (what the user says while it runs is the inbox's: Inbox);
// the column open (Cmd+B); the file the code panel reads, at a line; the
// questions waiting for the user (the turn's, and asked: studio.ask's
// side sets it), the input's glow, the strip above it, the tab's dot.
class Conversation {
	public final turns:Signal<Array<Turn>> = signal([]);
	public final open = signal(true);
	public final reading:Signal<Null<{file:String, line:Null<Int>}>> = signal(null);
	public final asked = signal(0);
	// the agent's start failed: why (a row of the chat's until it starts)
	public final trouble:Signal<Null<String>> = signal(null);
	// the input's field (focused by a card's "Something else…")
	public var field:Null<helder.ui.Node> = null;
	// (the truth: a signal's write lands at the event's end)
	var all:Array<Turn> = [];

	public function new() {}

	// a turn started (fresh) or changed: the last one's new state
	public function set(t:Turn, fresh:Bool) {
		all = fresh || all.length == 0 ? all.concat([t]) : all.slice(0, all.length - 1).concat([t]);
		turns(all);
	}

	public function list():Array<Turn>
		return all;

	// the questions waiting for the user (Questions': studio.ask's and ACP's permission asks)
	public function questions():Int
		return asked();

	// whether the agent waits for the user
	public function waits():Bool
		return questions() > 0;
}

