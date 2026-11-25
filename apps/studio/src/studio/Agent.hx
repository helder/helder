package studio;

// What the prompt bar talks to: a prompt about what is in focus (the whole
// app, a screen, a node), its turn told as events (text streamed, tools
// called, a plan, a question for the user) until it is Done or Failed. The
// user's own agent over ACP (AcpAgent, Agents), the studio's tools alone
// without one (LocalAgent); the hosted prompt box (helder.build's) plugs in
// here later. They act through the same tools as the studio's MCP server
// (Tools) and edit through its history.
interface Agent {
	function ask(prompt:String, context:AgentContext, on:AgentEvent->Void):Void;
	// the turn running stopped (it ends with Done("cancelled"))
	function cancel():Void;
	// the agent's process ended (the studio closing)
	function close():Void;
}

enum AgentEvent {
	Text(chunk:String);
	Thought(chunk:String);
	// a tool call, as it starts and as it goes (status: pending, in_progress, completed, failed)
	Tool(id:String, title:String, kind:String, status:String);
	// the agent's plan, whole each time
	Steps(steps:Array<{text:String, done:Bool}>);
	// a question for the user: answer with an option's index (-1: cancelled)
	Ask(question:String, options:Array<String>, answer:Int->Void);
	Done(reason:String);
	Failed(message:String);
}

typedef AgentContext = {
	// the screen in focus (null: the whole app), the node selected in it
	screen:Null<String>,
	selection:Null<{screen:String, file:String, start:Int, tag:String}>,
	// the studio's last build's errors ("file:line: message"; none: it built)
	problems:Array<String>,
	// the screens that threw when the studio ran them ("screen: file:line: why")
	?crashes:Array<String>,
}
