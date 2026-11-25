package studio;

import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// What the user tells the agent while it works, delivered without
// interrupting it: notes, each a direction (a message typed while it works)
// or an answer (to a question: studio.ask's side). Taken by whoever
// delivers them (an MCP tool result carries them; over ACP the ones left
// when a turn ends are its next prompt), then marked delivered: "seen".
class Inbox {
	public final notes:Signal<Array<Note>> = signal([]);
	// (the truth: a signal's write lands at the event's end)
	var all:Array<Note> = [];
	var next = 0;

	public function new() {}

	// a direction (turn: the one it was sent during, for the chat)
	public function direct(text:String, turn:Int):Note
		return add({id: ++next, kind: "direction", text: text, turn: turn, delivered: false});

	// an answer to a question
	public function answer(text:String, turn:Int):Note
		return add({id: ++next, kind: "answer", text: text, turn: turn, delivered: false});

	function add(n:Note):Note {
		set(all.concat([n]));
		return n;
	}

	public function list():Array<Note>
		return all;

	// the notes not delivered yet
	public function pending():Array<Note>
		return all.filter(n -> !n.delivered);

	// the notes not delivered yet, now delivered
	public function take():Array<Note> {
		var out = pending();
		if (out.length > 0) set([for (n in all) out.contains(n) ? ({id: n.id, kind: n.kind, text: n.text, turn: n.turn, delivered: true} : Note) : n]);
		return out;
	}

	// notes as the agent reads them
	public static function text(notes:Array<Note>):String
		return [for (n in notes) n.kind == "answer" ? n.text : 'The user says: ${n.text}'].join("\n");

	function set(l:Array<Note>) {
		all = l;
		notes(l);
	}
}

typedef Note = {
	id:Int,
	// "direction" or "answer"
	kind:String,
	text:String,
	turn:Int,
	delivered:Bool,
}
