package studio;

import studio.Agent.AgentEvent;

using StringTools;

// The prompt's turn as the prompt bar shows it, folded from the agent's
// events (Turn.add: a new value each time): the reply streamed so far, the
// tools called (each by its id, its last title and status), the plan, the
// question waiting for the user, how it ended (null: it runs).
typedef Turn = {
	prompt:String,
	text:String,
	thought:String,
	tools:Array<{id:String, title:String, kind:String, status:String}>,
	steps:Array<{text:String, done:Bool}>,
	ask:Null<{question:String, options:Array<String>, answer:Int->Void}>,
	end:Null<String>,
	error:Null<String>,
	// the studio's build failed after it: its first error
	build:Null<String>,
	// a tool ran since its last text (the next text a new paragraph)
	?gap:Bool,
}

class Turns {
	public static function start(prompt:String):Turn
		return {prompt: prompt, text: "", thought: "", tools: [], steps: [], ask: null, end: null, error: null, build: null};

	public static function add(t:Turn, e:AgentEvent):Turn {
		var n:Turn = Reflect.copy(t);
		switch e {
			case Text(c):
				// (a message after a tool call: the agent's next, its own paragraph)
				n.text = t.gap == true && t.text != "" && !t.text.endsWith("\n\n") ? t.text + "\n\n" + c : t.text + c;
				n.gap = false;
			case Thought(c):
				n.thought = t.thought + c;
			case Tool(id, title, kind, status):
				n.gap = true;
				var known = Lambda.find(t.tools, x -> x.id == id);
				n.tools = known == null ? t.tools.concat([{id: id, title: title, kind: kind, status: status}]) : [
					for (x in t.tools)
						x.id != id ? x : {
							id: id,
							title: title == "" ? x.title : title,
							kind: kind == "" ? x.kind : kind,
							status: status == "" ? x.status : status
						}
				];
			case Steps(steps):
				n.steps = steps;
			case Ask(q, options, answer):
				n.ask = {question: q, options: options, answer: answer};
			case Done(reason):
				n.end = reason;
				n.ask = null;
			case Failed(message):
				n.end = "failed";
				n.error = message;
				n.ask = null;
		}
		return n;
	}

	// (the studio's build failing as it ended: its first error)
	public static function broken(t:Turn, problem:String):Turn {
		var n:Turn = Reflect.copy(t);
		n.build = problem;
		return n;
	}

	// (its question answered: gone from the bar)
	public static function answered(t:Turn):Turn {
		var n:Turn = Reflect.copy(t);
		n.ask = null;
		return n;
	}

	// (a reply cut at places in it, in order: the chat's notes in its flow)
	public static function split(text:String, at:Array<Int>):Array<String> {
		var out = [], from = 0;
		for (a in at) {
			var to = Std.int(Math.max(from, Math.min(a, text.length)));
			out.push(text.substring(from, to));
			from = to;
		}
		out.push(text.substr(from));
		return out;
	}

	public static function running(t:Null<Turn>):Bool
		return t != null && t.end == null;
}
