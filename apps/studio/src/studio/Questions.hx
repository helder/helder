package studio;

import helder.image.Image;

import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import studio.Presence.Peer;

using StringTools;

// The agents' questions (studio.ask): each a question and its options, an
// option pointing at what is on the canvas (a design's frame, a screen) or
// an image, or text alone. Asked in the chat (Chat: a card, its thumbnails;
// picked there alone, the picked frame ringed on the canvas too), answered
// by a pick or the user's own words ("Something else…": the input's next
// message). The answer reaches the agent through the inbox (its next tool
// result carries it), or the call that waits for it (wait).
class Questions {
	public final all:Signal<Array<Question>> = signal([]);
	// the question the input answers next (its card's "Something else…")
	public final replying:Signal<Null<String>> = signal(null);
	// (the truths: a signal's write lands at the event's end)
	var list:Array<Question> = [];
	var answering:Null<String> = null;
	var next = 0;
	final studio:Studio;

	public function new(studio)
		this.studio = studio;

	// a question asked (by: its agent; options as studio.ask gives them,
	// each checked against the canvas: a thrown message names what is not there)
	public function ask(by:Null<Peer>, question:String, options:Array<Dynamic>, multiple:Bool):Question {
		if (question == null || question.trim() == "") throw "a question is needed";
		if (options == null || options.length == 0) throw "options are needed: [{label, frame?, screen?, image?}]";
		var choices:Array<Offer> = [];
		for (k => o in options) {
			var label:String = o.label ?? o.id;
			if (label == null) throw 'option ${k + 1}: a label is needed';
			choices.push({
				id: o.id ?? '${k + 1}',
				label: label,
				note: o.note,
				screen: o.frame != null ? place(o.frame) : o.screen != null ? place(o.screen) : null,
				image: o.image == null ? null : image(o.image)
			});
		}
		var q:Question = {
			id: 'q${++next}',
			agent: by?.id,
			by: by?.name ?? "Agent",
			colour: by?.colour ?? Theme.AGENTS[0],
			question: question.trim(),
			options: choices,
			multiple: multiple,
			picked: [],
			text: null,
			answered: false,
			turn: studio.talk.list().length - 1,
			at: here(),
			waited: false
		};
		set(list.concat([q]));
		return q;
	}

	// an ACP agent's permission ask (by: its name and colour): the same card,
	// text options (their ids the options' indices), answered through reply
	public function permission(by:{name:String, colour:String}, question:String, options:Array<String>,
			reply:(picked:Array<String>, text:Null<String>) -> Void):Question {
		var q:Question = {
			id: 'q${++next}',
			agent: null,
			by: by.name,
			colour: by.colour,
			question: question,
			options: [for (k => o in options) {id: '$k', label: o, note: null, screen: null, image: null}],
			multiple: false,
			picked: [],
			text: null,
			answered: false,
			turn: studio.talk.list().length - 1,
			at: here(),
			waited: true,
			reply: reply
		};
		set(list.concat([q]));
		return q;
	}

	// (how much of the turn's reply there is now: the card's place in it)
	function here():Int {
		var l = studio.talk.list();
		return l.length == 0 ? 0 : l[l.length - 1].text.length;
	}

	// a question no longer asked (its turn ended, the agent gone): closed, nothing answered
	public function close(id:String) {
		var q = get(id);
		if (q == null || q.answered) return;
		update(q, n -> n.answered = true);
		if (answering == id) replyTo(null);
	}

	public function get(id:String):Null<Question>
		return Lambda.find(list, q -> q.id == id);

	public function open():Array<Question>
		return list.filter(q -> !q.answered);

	// an option picked in its card: one question's answer at once; several's, picked and taken back until sent
	public function pick(id:String, choice:String) {
		var q = get(id);
		if (q == null || q.answered) return;
		if (!q.multiple) {
			answer(q, [choice], null);
			return;
		}
		update(q, n -> n.picked = q.picked.contains(choice) ? q.picked.filter(c -> c != choice) : q.picked.concat([choice]));
	}

	// a question of several picks sent as they are
	public function send(id:String) {
		var q = get(id);
		if (q != null && !q.answered && q.picked.length > 0) answer(q, q.picked, null);
	}

	// the user's own words for it (typed after "Something else…")
	public function reply(id:String, text:String) {
		var q = get(id);
		if (q != null && !q.answered) answer(q, q.picked, text);
	}

	// the input's next message answers this one
	public function replyTo(id:Null<String>) {
		answering = id;
		replying(id);
	}

	// the question the input answers now (null: none)
	public function answeringNow():Null<String>
		return answering;

	// a call waits for it (studio.ask's wait: its answer the call's, not the
	// inbox's), or no longer (it gave up: a later answer the inbox's)
	public function wait(id:String, on = true)
		update(get(id), n -> n.waited = on);

	// what the agent reads of an answer
	public static function said(q:Question):String {
		var labels = [for (c in q.options) if (q.picked.contains(c.id)) c.label];
		var what = labels.join(", ") + (q.text == null ? "" : (labels.length > 0 ? "; " : "") + q.text);
		return 'The user answered "${q.question}": $what.' + (q.picked.length > 0 ? ' (picked: ${q.picked.join(", ")})' : "");
	}

	function answer(q:Question, picked:Array<String>, text:Null<String>) {
		var n = update(q, n -> {
			n.options = n.options.map(keep);
			n.picked = picked;
			n.text = text;
			n.answered = true;
		});
		if (answering == q.id) replyTo(null);
		if (n.reply != null) n.reply(n.picked, n.text) else if (!n.waited) studio.inbox.answer(said(n), n.turn);
		studio.log("answered", {question: n.question, picked: n.picked, text: n.text});
		studio.answered();
	}

	// (an option's picture as it is now, the card's once answered: the sketches
	// go when the agent is done with them)
	function keep(o:Offer):Offer {
		var info = o.screen == null ? null : studio.project?.screen(o.screen);
		if (info == null) return o;
		var k:Offer = Reflect.copy(o);
		if (info.source.match(Design(_))) k.kept = {markup: studio.designs.copy(info.name), width: info.width > 0 ? info.width : 390, height: info.height > 0 ? info.height : 844}
		else k.still = studio.previews?.screen(info.name)?.image.peek();
		return k;
	}

	// (a frame or a screen named as the project names it: <file>#<name>, Flow/Screen)
	function place(name:String):String {
		var p = studio.project;
		if (p == null) throw "no project open";
		var s = p.screen(name) ?? Lambda.find(p.screens, s -> s.source.match(Design(_)) && name.endsWith("#" + s.label) && (p.dir + "/" + name.substr(0, name.lastIndexOf("#"))) == s.file);
		if (s == null) throw 'no frame or screen $name on the canvas (${[for (x in p.screens) x.name].join(", ")})';
		return s.name;
	}

	function image(path:String):String {
		var p = studio.project;
		if (p == null) throw "no project open";
		var f = haxe.io.Path.normalize(haxe.io.Path.isAbsolute(path) ? path : p.dir + "/" + path);
		if (!f.startsWith(p.dir + "/") || !Files.exists(f)) throw '$path: no such image in the project';
		return f;
	}

	function update(q:Null<Question>, f:Question->Void):Null<Question> {
		if (q == null) return null;
		var n:Question = Reflect.copy(q);
		f(n);
		set([for (x in list) x.id == q.id ? n : x]);
		return n;
	}

	function set(l:Array<Question>) {
		list = l;
		all(l);
		studio.talk.asked(l.filter(q -> !q.answered).length);
	}
}

typedef Question = {
	id:String,
	// its agent (Presence's id; null: none known), its name and colour
	agent:Null<String>,
	by:String,
	colour:String,
	question:String,
	options:Array<Offer>,
	multiple:Bool,
	picked:Array<String>,
	text:Null<String>,
	answered:Bool,
	// the chat's turn it was asked in, its place in that turn's reply
	turn:Int,
	at:Int,
	// a call waits for its answer (studio.ask's wait)
	waited:Bool,
	// (an ACP agent's permission ask: its answer given here, not the inbox's)
	?reply:(picked:Array<String>, text:Null<String>) -> Void,
}

// an option: on the canvas (screen: a design's frame's or a screen's name), an image (a project's file), or text alone
typedef Offer = {
	id:String,
	label:String,
	note:Null<String>,
	screen:Null<String>,
	image:Null<String>,
	// (kept when answered, its thumbnail after its frame is gone: a design
	// frame's markup at its size, a screen's last image)
	?kept:{markup:Any, width:Float, height:Float},
	?still:Image,
}
