package studio;

import helder.gfx.Color;
import helder.markdown.Markdown;
import helder.markdown.MarkdownView;
import helder.ui.*;
import helder.ui.view.UiFlow.Popover;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Theme.c;
import studio.Turn;

using StringTools;

// The chat column (the watched shell's, left of the canvas): each turn the
// user's prompt in a bubble, then the agent's: its reply as Markdown (links
// the studio knows as chips: Replies), its plan one dim line, "Thinking…"
// while it thinks, the files it changed (Undo; the ones before folded), a
// failed build's row, its question as a card, what the user said while it
// worked where it said it (the inbox's notes: "sent while working", then
// "seen"; its tools are not shown: plumbing the user can't act on); at the
// bottom the questions waiting (a quiet strip) and the input, with the
// agent's chip (its menu a popup above it) and send, which while the agent
// works is its mark, pulsing in its colour (a press stops it). Every input
// of the studio's is here: the canvas is to watch.
class Chat implements Markup {
	public static function view(studio:Studio):View {
		// (the log follows what comes while it is at its end: a reply, a card, a note)
		var follow = true;
		effect(() -> {
			var t = studio.talk.turns();
			'${t.length} ${t.length == 0 ? 0 : t[t.length - 1].text.length} ${studio.questions.all().length} ${studio.questions.open().length} ${studio.inbox.notes().length} ${studio.marks.changes().length}';
		}, _ -> if (follow) toEnd());
		return <view tag="chat" width={Theme.CHAT} shrink={0} background={c("chat")} border-width="0 1 0 0" border-color={c("hair")} min-height={0}
			transition="fade slide-left(24)">
			<scroll tag="chat-log" grow={1} min-height={0} padding="18 18 8" row-gap={14} font-size={Theme.CHAT_SIZE} color={c("ink2")}
				ref={(n:Node) -> {
					log = n;
					n.onScroll = () -> follow = n.scrollY >= n.contentHeight - n.height - 24;
				}}>
				<For each={[for (i in 0...studio.talk.turns().length) i]}>{(i:Read<Int>) -> turn(studio, i())}</For>
				<Show when={studio.talk.trouble() != null}>
					<view tag="chat-trouble" padding="8 10" radius={Theme.CHIP} background={c("error-soft")}>
						<text color={c("error")} font-size={12} max-lines={6} text-overflow="ellipsis">{studio.talk.trouble() ?? ""}</text>
					</view>
				</Show>
				<For each={studio.marks.changes().filter(c -> c.turn < 0)} by={(c:Marks.Changed) -> c.id}>{(c:Read<Marks.Changed>) -> change(studio, c)}</For>
				<For each={studio.questions.all().filter(q -> q.turn < 0)} by={(q:Questions.Question) -> q.id}>{(q:Read<Questions.Question>) -> Asks.card(studio, q)}</For>
				<view tag="chat-end" height={16} shrink={0}/>
			</scroll>
			<view padding="12 14 14" row-gap={8} shrink={0}>
				<Show when={studio.talk.questions() > 0}>
					<view:button tag="chat-questions" role="button" label="The questions for you" direction="row" align-items="center" column-gap={6}
						cursor="pointer" color={c("dim")} onPress={() -> toEnd()}>
						<view width={5} height={5} radius={3} background={Color.parse(waiter(studio).colour)}/>
						<text font-size={11}>{questions(studio.talk.questions())}</text>
					</view:button>
				</Show>
				{input(studio, false)}
			</view>
		</view>;
	}

	// (the chat's scroller: the questions' strip scrolls it to them, at its end)
	static var log:Null<Node> = null;

	// (the log at its end, once laid out with what came)
	static function toEnd() {
		function end() {
			var l = log;
			if (l != null) l.scrollY = Math.max(0, l.contentHeight + l.style.padding.bottom - l.height);
		}
		// (again once a card's lift and the panel below have settled)
		Clock.after(0.02, end);
		Clock.after(0.4, end);
	}

	static function questions(n:Int):String
		return n == 1 ? "1 question for you" : '$n questions for you';

	// (the agent at work: a turn running)
	public static function working(studio:Studio):Bool {
		var t = studio.talk.turns();
		return t.length > 0 && Turns.running(t[t.length - 1]);
	}

	static function bubble(text:String):View
		return <view tag="chat-you" align-self="flex-end" max-width={260} padding="8 12" radius={Theme.CARD} background={c("bubble")}>
			<text color={c("ink")} font-size={Theme.CHAT_SIZE} line-height={1.55}>{text}</text>
		</view>;

	// a note the user sent while the agent worked: its bubble, marked; "seen" once delivered
	static function note(n:Read<Inbox.Note>):View
		return <view tag={"chat-note-" + n().id} align-self="flex-end" align-items="flex-end" row-gap={3}>
			{bubble(n().text)}
			<text tag="chat-note-mark" font-size={11} color={c("dim")}>{n().delivered ? "sent while working · seen" : "sent while working"}</text>
		</view>;

	// who the user's answer is waited for by: the first open question's agent, else the prompt's
	public static function waiter(studio:Studio):{name:String, colour:String} {
		var q = studio.questions.open()[0];
		return q != null ? {name: q.by, colour: q.colour} : {name: studio.agentName(), colour: studio.agentColour()};
	}

	// a turn: the prompt, then the agent's part
	static function turn(studio:Studio, i:Int):View {
		function t():Turn {
			var all = studio.talk.turns();
			return i < all.length ? all[i] : Turns.start("");
		}
		var steps = signal(false), changed = signal(false);
		return <view tag={"chat-turn-" + i} row-gap={8}>
			<Show when={t().prompt != ""}>{bubble(t().prompt)}</Show>
			<Show when={t().steps.length > 0}>
				<view tag="chat-plan" row-gap={2}>
					<text color={c("dim")} font-size={12} cursor="pointer" onClick={_ -> steps(!steps.peek())}>{'${t().steps.length} steps ' + (steps() ? "▾" : "▸")}</text>
					<Show when={steps()}>
						<For each={t().steps.map(s -> s)}>{(s:Read<{text:String, done:Bool}>) ->
							<text color={c("dim")} font-size={12}>{(s().done ? "✓ " : "· ") + s().text}</text>
						}</For>
					</Show>
				</view>
			</Show>
			{reply(studio, () -> Turns.split(t().text, notes(studio, i).map(n -> n.at))[0])}
			<For each={notes(studio, i)} by={(n:Inbox.Note) -> n.id}>{(n:Read<Inbox.Note>) ->
				<view row-gap={8}>
					{note(n)}
					{reply(studio, () -> after(t(), notes(studio, i), n().id))}
				</view>
			}</For>
			<Show when={Turns.running(t()) && t().text == ""}>
				<view tag="chat-thinking" direction="row" align-items="center" column-gap={8}>
					<view tag="chat-thinking-mark" width={8} height={8} radius={4} background={Color.parse(studio.agentColour())}
						ref={(n:Node) -> Watch.pulse(n, () -> Turns.running(t()))}/>
					<text color={c("dim")} font-size={12}>{studio.agentStarting() ? 'Starting ${studio.agentName()}…' : t().thought != "" ? "Thinking…" : ""}</text>
				</view>
			</Show>
			<Show when={t().build != null || t().error != null}>{failure(studio, t)}</Show>
			<Show when={Replies.fold(changes(studio, i), changed()).folded > 0}>
				<text tag="chat-changes-folded" font-size={12} color={c("ink3")} cursor="pointer" onClick={_ -> changed(true)}>{
					'Made ${changes(studio, i).length} changes ▸'
				}</text>
			</Show>
			<For each={Replies.fold(changes(studio, i), changed()).shown} by={(c:Marks.Changed) -> c.id}>{(c:Read<Marks.Changed>) -> change(studio, c)}</For>
			<For each={studio.questions.all().filter(q -> q.turn == i)} by={(q:Questions.Question) -> q.id}>{(q:Read<Questions.Question>) -> Asks.card(studio, q)}</For>
		</view>;
	}

	// (the reply's part after a note, to the next one)
	static function after(t:Turn, notes:Array<Inbox.Note>, id:Int):String {
		var k = Lambda.findIndex(notes, n -> n.id == id);
		return k < 0 ? "" : Turns.split(t.text, notes.map(n -> n.at))[k + 1];
	}

	// (a turn's changes: one a file)
	static function changes(studio:Studio, i:Int):Array<Marks.Changed>
		return studio.marks.changes().filter(c -> c.turn == i);

	// (the directions sent during a turn, in the order of their places in its reply)
	static function notes(studio:Studio, i:Int):Array<Inbox.Note> {
		var out = studio.inbox.notes().filter(n -> n.turn == i && n.kind == "direction");
		out.sort((a, b) -> a.at - b.at);
		return out;
	}

	// an agent's edits of a file: "Changed app.helder · Undo" (Undo while its last is the one undo takes)
	static function change(studio:Studio, x:Read<Marks.Changed>):View
		return <view tag={"chat-change-" + x().id} direction="row" align-items="center" column-gap={6} font-size={12} color={c("ink3")}>
			<view width={6} height={6} radius={3} shrink={0} background={Color.parse(x().colour)}/>
			<text min-width={0} shrink={1} max-lines={1} text-overflow="ellipsis">{'${x().by} changed ${x().file}' + (x().count > 1 ? ' (${x().count} edits)' : "")}</text>
			<Show when={x().entry != null && studio.docs.nextUndo() == x().entry}>
				<text shrink={0}>·</text>
				<text tag="chat-change-undo" shrink={0} color={c("ink")} cursor="pointer" onClick={_ -> studio.undo()}>Undo</text>
			</Show>
		</view>;

	// the reply's Markdown, kept as it streams (MarkdownView.update), its chips the studio's
	static function reply(studio:Studio, text:Void->String):MarkdownView {
		var dir = studio.project?.dir;
		var v = new MarkdownView({
			doc: Markdown.parse(""),
			scroll: false,
			codeFont: Theme.CODE,
			codeSize: Theme.CODE_SIZE,
			onLink: studio.follow,
			linkSlot: href -> Replies.chip(href, dir)
		});
		v.tag = "chat-reply";
		effect(() -> text(), s -> v.update(Replies.parse(s, dir, f -> Files.exists(f) && !Files.isDirectory(f))));
		return v;
	}

	// a failed build (its first error, where: a file's chip) or the turn's own failure
	static function failure(studio:Studio, t:Void->Turn):View {
		function where():Null<String> {
			var b = t().build;
			var m = b == null ? null : ~/^([^\s:]+:\d+):/;
			return m != null && m.match(b) ? m.matched(1) : null;
		}
		return <view tag="chat-failed" direction="row" column-gap={6} align-items="flex-start" padding="8 10" radius={Theme.CHIP}
			background={c("error-soft")}>
			<Show when={where() != null}>
				<text tag="chat-failed-file" slot="chip-file" shrink={0} cursor="pointer" onClick={_ -> studio.follow(where())}>{where() ?? ""}</text>
			</Show>
			<text grow={1} min-width={0} color={c("error")} font-size={12} max-lines={4} text-overflow="ellipsis">{
				t().build != null ? "Build failed · " + (where() == null ? t().build : t().build.substr(where().length + 1).trim()) : (t().error ?? "")
			}</text>
		</view>;
	}

	// the input: the prompt (blank: the sheet's first, bigger), the agent's
	// chip (its menu: the agents found, a popup above it), send; Enter sends
	// (while the agent works: a note for it). While it works, with nothing
	// typed, send is the agent's mark, pulsing (a press stops the turn).
	// Glows in the asker's colour while a question waits.
	public static function input(studio:Studio, blank:Bool):View {
		var text = signal(""), menu = signal(false);
		function send() {
			var p = text.peek();
			if (StringTools.trim(p) == "") return;
			studio.ask(p);
			text("");
		}
		return <view tag="chat-input" matched="prompt" padding={blank ? "16 16 12" : "10 12"} row-gap={blank ? 14 : 8} radius={blank ? 14 : Theme.CARD}
			background={c("card")} border-width={1}
			border-color={studio.talk.waits() ? Color.parse(waiter(studio).colour) : c(blank ? "hair" : "hair2")}
			shadow={blank ? "0 24 80 rgba(0,0,0,0.35)" : "none"}>
			<field tag="prompt" slot="ask-input" label="Prompt" value={text} min-height={blank ? 48 : 22} font-size={blank ? 16 : Theme.CHAT_SIZE}
				placeholder={blank ? "What do you want to make?" : "Reply…"} ref={(n:Node) -> studio.talk.field = n}
				onInput={e -> text(e.text)} onKeyDown={e -> if (e.key == Key.ENTER) send()}/>
			<view direction="row" align-items="center" column-gap={8}>
				<view:button tag="agent-chip" role="button" label={"The agent: " + studio.agentName()} focusable direction="row" align-items="center"
					column-gap={6} height={blank ? 28 : 22} padding="0 8" radius={Theme.CHIP} background={c("bubble")} color={c("ink2")} cursor="pointer"
					onPress={() -> menu(!menu.peek())}>
					<view width={blank ? 8 : 6} height={blank ? 8 : 6} radius={4} background={Color.parse(studio.agentColour())}/>
					<text font-size={blank ? 12 : 11}>{studio.agentName()}</text>
					<image src={Icons.chevronDown} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("ink3")}/>
					<Popover open={menu} placement="above" gap={6} onDismiss={() -> menu(false)}>{agents(studio, menu)}</Popover>
				</view:button>
				<view grow={1}/>
				<Show when={working(studio) && text() == ""} fallback={
					<view:button tag="send" role="button" label="Send" focusable width={blank ? 32 : 28} height={blank ? 32 : 28} radius={8}
						background={text() == "" ? c("hair2") : c("ink")} color={text() == "" ? c("ink3") : c("ground")} align-items="center" justify="center"
						cursor="pointer" onPress={send}>
						<image src={Icons.arrowUp} width={Theme.ICON_S} height={Theme.ICON_S}/>
					</view:button>
				}>
					<view:button tag="chat-stop" role="button" label={studio.agentName() + " is working: stop"} focusable width={28} height={28} radius={8}
						background={c("hair2")} align-items="center" justify="center" cursor="pointer" onPress={() -> studio.stopTurn()}>
						<view tag="chat-working" width={10} height={10} radius={5} background={Color.parse(studio.agentColour())}
							ref={(n:Node) -> Watch.pulse(n, () -> working(studio))}/>
					</view:button>
				</Show>
			</view>
		</view>;
	}

	// the agents found (Agents), the one in use marked; another taken for the next prompt
	static function agents(studio:Studio, menu:helder.view.graph.Signal<Bool>):View
		return <view tag="agent-menu" slot="floating" padding={4} row-gap={2} min-width={180} shadow={Theme.POPOVER}>
			<For each={Agents.found()}>{(id:Read<String>) ->
				<view:button tag={"agent-" + id()} slot="menu-item" role="button" label={Agents.label(id())} focusable
					data-on={Agents.label(id()) == studio.agentName() ? "true" : "false"} onPress={() -> {
						menu(false);
						studio.useAgent(id());
					}}>
					<view width={6} height={6} radius={3} background={Color.parse(Agents.colour(id()))}/>
					<text>{Agents.label(id())}</text>
				</view:button>
			}</For>
		</view>;
}
