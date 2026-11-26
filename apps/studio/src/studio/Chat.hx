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
// failed build's row, its questions as cards and what the user said while it
// worked, each where it came in the reply (the inbox's notes: "sent while working", then
// "seen"; its tools are not shown: plumbing the user can't act on); at the
// bottom the questions waiting (a quiet strip) and the input, with the
// agent's chip (its menu a popup above it) and send, which while the agent
// works is its mark, pulsing in its colour (a press stops it). Every input
// of the studio's is here: the canvas is to watch.
@:renderer(helder.ui.view.NodeRenderer)
class Chat implements Markup {
	public static function view(studio:Studio):View {
		// (the log follows what comes while it is at its end: a reply, a card, a note)
		var follow = true;
		effect(() -> {
			var t = studio.talk.turns();
			'${t.length} ${t.length == 0 ? 0 : t[t.length - 1].text.length} ${studio.questions.all().length} ${studio.questions.open().length} ${studio.inbox.notes().length} ${studio.marks.changes().length}';
		}, _ -> if (follow) toEnd());
		return <view tag="chat" width={Theme.CHAT} flexShrink={0} background={c("chat")} borderWidth="0 1 0 0" borderColor={c("hair")} minHeight={0}
			transition="fade slide-left(24)">
			<scroll tag="chat-log" flexGrow={1} minHeight={0} padding="18 18 8" rowGap={14} fontSize={Theme.CHAT_SIZE} color={c("ink2")}
				ref={(n:Node) -> {
					log = n;
					n.onScroll = () -> follow = n.scrollY >= n.contentHeight - n.height - 24;
				}}>
				<For each={[for (i in 0...studio.talk.turns().length) i]}>{(i:Read<Int>) -> turn(studio, i())}</For>
				<Show when={studio.talk.trouble() != null}>
					<view tag="chat-trouble" padding="8 10" borderRadius={Theme.CHIP} background={c("error-soft")}>
						<text color={c("error")} fontSize={12} lineClamp={6} textOverflow="ellipsis">{studio.talk.trouble() ?? ""}</text>
					</view>
				</Show>
				<For each={studio.marks.changes().filter(c -> c.turn < 0)} by={(c:Marks.Changed) -> c.id}>{(c:Read<Marks.Changed>) -> change(studio, c)}</For>
				<For each={studio.questions.all().filter(q -> q.turn < 0)} by={(q:Questions.Question) -> q.id}>{(q:Read<Questions.Question>) -> Asks.card(studio, q)}</For>
				<view tag="chat-end" height={16} flexShrink={0}/>
			</scroll>
			<view padding="12 14 14" rowGap={8} flexShrink={0}>
				<Show when={studio.talk.questions() > 0}>
					<button tag="chat-questions" aria-label="The questions for you" flexDirection="row" alignItems="center" columnGap={6}
						cursor="pointer" color={c("dim")} onPress={() -> toEnd()}>
						<view width={5} height={5} borderRadius={3} background={Color.parse(waiter(studio).colour)}/>
						<text fontSize={11}>{questions(studio.talk.questions())}</text>
					</button>
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
		return <view tag="chat-you" alignSelf="flex-end" maxWidth={260} padding="8 12" borderRadius={Theme.CARD} background={c("bubble")}>
			<text color={c("ink")} fontSize={Theme.CHAT_SIZE} lineHeight={1.55}>{text}</text>
		</view>;

	// a note the user sent while the agent worked: its bubble, marked; "seen" once delivered
	static function note(n:Read<Inbox.Note>):View
		return <view tag={"chat-note-" + n().id} alignSelf="flex-end" alignItems="flex-end" rowGap={3}>
			{bubble(n().text)}
			<text tag="chat-note-mark" fontSize={11} color={c("dim")}>{n().delivered ? "sent while working · seen" : "sent while working"}</text>
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
		return <view tag={"chat-turn-" + i} rowGap={8}>
			<Show when={t().prompt != ""}>{bubble(t().prompt)}</Show>
			<Show when={t().steps.length > 0}>
				<view tag="chat-plan" rowGap={2}>
					<text color={c("dim")} fontSize={12} cursor="pointer" onPress={_ -> steps(!steps.peek())}>{'${t().steps.length} steps ' + (steps() ? "▾" : "▸")}</text>
					<Show when={steps()}>
						<For each={t().steps.map(s -> s)}>{(s:Read<{text:String, done:Bool}>) ->
							<text color={c("dim")} fontSize={12}>{(s().done ? "✓ " : "· ") + s().text}</text>
						}</For>
					</Show>
				</view>
			</Show>
			{reply(studio, () -> Turns.split(t().text, places(studio, i).map(p -> p.at))[0])}
			<For each={places(studio, i)} by={(p:Place) -> p.key}>{(p:Read<Place>) ->
				<view rowGap={8}>
					{p().note != null ? note(() -> p().note) : Asks.card(studio, () -> p().ask)}
					{reply(studio, () -> after(t(), places(studio, i), p().key))}
				</view>
			}</For>
			<Show when={Turns.running(t()) && t().text == ""}>
				<view tag="chat-thinking" flexDirection="row" alignItems="center" columnGap={8}>
					<view tag="chat-thinking-mark" width={8} height={8} borderRadius={4} background={Color.parse(studio.agentColour())}
						ref={(n:Node) -> Watch.pulse(n, () -> Turns.running(t()))}/>
					<text tag="chat-status" color={c("dim")} fontSize={12} lineClamp={1} textOverflow="ellipsis">{status(studio, t())}</text>
				</view>
			</Show>
			<Show when={t().build != null || t().crash != null || t().error != null}>{failure(studio, t)}</Show>
			<Show when={Replies.fold(changes(studio, i), changed()).folded > 0}>
				<text tag="chat-changes-folded" fontSize={12} color={c("ink3")} cursor="pointer" onPress={_ -> changed(true)}>{
					'Made ${changes(studio, i).length} changes ▸'
				}</text>
			</Show>
			<For each={Replies.fold(changes(studio, i), changed()).shown} by={(c:Marks.Changed) -> c.id}>{(c:Read<Marks.Changed>) -> change(studio, c)}</For>
		</view>;
	}

	// (the reply's part after a place, to the next one)
	static function after(t:Turn, places:Array<Place>, key:String):String {
		var k = Lambda.findIndex(places, p -> p.key == key);
		return k < 0 ? "" : Turns.split(t.text, places.map(p -> p.at))[k + 1];
	}

	// (the turn's one dim line until its first words: starting, what the agent
	// says it is about to do (studio.working's note, its status), else thinking)
	public static function status(studio:Studio, t:Turn):String {
		if (studio.agentStarting()) return 'Starting ${studio.agentName()}…';
		var name = studio.agentName(), peers = studio.presence.peers().filter(p -> p.working && p.status != "");
		var p = Lambda.find(peers, p -> p.name == name) ?? peers[0];
		return p != null ? p.status : t.thought != "" ? "Thinking…" : "";
	}

	// (a turn's changes: one a file)
	static function changes(studio:Studio, i:Int):Array<Marks.Changed>
		return studio.marks.changes().filter(c -> c.turn == i);

	// (what sits in a turn's reply where it came: the directions sent during it,
	// the questions asked in it; in the order of their places, as they came)
	static function places(studio:Studio, i:Int):Array<Place> {
		var out:Array<Place> = [
			for (n in studio.inbox.notes())
				if (n.turn == i && n.kind == "direction") {key: "note" + n.id, at: n.at, note: n, ask: null}
		].concat([for (q in studio.questions.all()) if (q.turn == i) {key: q.id, at: q.at, note: null, ask: q}]);
		haxe.ds.ArraySort.sort(out, (a, b) -> a.at - b.at);
		return out;
	}
	// an agent's edits of a file: "Changed app.helder · Undo" (Undo while its last is the one undo takes)
	static function change(studio:Studio, x:Read<Marks.Changed>):View
		return <view tag={"chat-change-" + x().id} flexDirection="row" alignItems="center" columnGap={6} fontSize={12} color={c("ink3")}>
			<view width={6} height={6} borderRadius={3} flexShrink={0} background={Color.parse(x().colour)}/>
			<text minWidth={0} flexShrink={1} lineClamp={1} textOverflow="ellipsis">{'${x().by} changed ${x().file}' + (x().count > 1 ? ' (${x().count} edits)' : "")}</text>
			<Show when={x().entry != null && studio.docs.nextUndo() == x().entry}>
				<text flexShrink={0}>·</text>
				<text tag="chat-change-undo" flexShrink={0} color={c("ink")} cursor="pointer" onPress={_ -> studio.undo()}>Undo</text>
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

	// a failed build (its first error, where: a file's chip), a screen that
	// crashed when run, or the turn's own failure
	static function failure(studio:Studio, t:Void->Turn):View {
		function where():Null<String> {
			var b = t().build ?? t().crash;
			var m = b == null ? null : ~/^([^\s:]+:\d+):/;
			return m != null && m.match(b) ? m.matched(1) : null;
		}
		return <view tag="chat-failed" flexDirection="row" columnGap={6} alignItems="flex-start" padding="8 10" borderRadius={Theme.CHIP}
			background={c("error-soft")}>
			<Show when={where() != null}>
				<text tag="chat-failed-file" slot="chip-file" flexShrink={0} cursor="pointer" onPress={_ -> studio.follow(where())}>{where() ?? ""}</text>
			</Show>
			<text flexGrow={1} minWidth={0} color={c("error")} fontSize={12} lineClamp={4} textOverflow="ellipsis">{
				t().build != null ? "Build failed · " + rest(t().build, where()) : t().crash != null ? "Crashed · " + rest(t().crash, where()) : (t().error ?? "")
			}</text>
		</view>;
	}

	// (a failure's text after its file:line, when it starts with one)
	static function rest(s:String, where:Null<String>):String
		return where == null ? s : s.substr(where.length + 1).trim();

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
		return <view tag="chat-input" matched="prompt" padding={blank ? "16 16 12" : "10 12"} rowGap={blank ? 14 : 8} borderRadius={blank ? 14 : Theme.CARD}
			background={c("card")} borderWidth={1}
			borderColor={studio.talk.waits() ? Color.parse(waiter(studio).colour) : c(blank ? "hair" : "hair2")}
			boxShadow={blank ? "0 24 80 rgba(0,0,0,0.35)" : "none"}>
			<For each={blank || studio.about() == null ? [] : [studio.about()]} by={(n:String) -> n}>{(n:Read<String>) -> about(studio, n())}</For>
			<field tag="prompt" slot="ask-input" aria-label="Prompt" value={text} minHeight={blank ? 48 : 22} fontSize={blank ? 16 : Theme.CHAT_SIZE}
				placeholder={blank ? "What do you want to make?" : "Reply…"} ref={(n:Node) -> studio.talk.field = n}
				onInput={e -> text(e.text)} onKeyDown={e -> if (e.key == Key.ENTER) send()}/>
			<view flexDirection="row" alignItems="center" columnGap={8}>
				<button tag="agent-chip" aria-label={"The agent: " + studio.agentName()} flexDirection="row" alignItems="center"
					columnGap={6} height={blank ? 28 : 22} padding="0 8" borderRadius={Theme.CHIP} background={c("bubble")} color={c("ink2")} cursor="pointer"
					onPress={() -> menu(!menu.peek())}>
					<view width={blank ? 8 : 6} height={blank ? 8 : 6} borderRadius={4} background={Color.parse(studio.agentColour())}/>
					<text fontSize={blank ? 12 : 11}>{studio.agentName()}</text>
					<image src={Icons.chevronDown} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("ink3")}/>
					<Popover open={menu} placement="above" gap={6} onDismiss={() -> menu(false)}>{agents(studio, menu)}</Popover>
				</button>
				<view flexGrow={1}/>
				<Show when={working(studio) && text() == ""} fallback={
					<button tag="send" aria-label="Send" width={blank ? 32 : 28} height={blank ? 32 : 28} borderRadius={8}
						background={text() == "" ? c("hair2") : c("ink")} color={text() == "" ? c("ink3") : c("ground")} alignItems="center" justifyContent="center"
						cursor="pointer" onPress={send}>
						<image src={Icons.arrowUp} width={Theme.ICON_S} height={Theme.ICON_S}/>
					</button>
				}>
					<button tag="chat-stop" aria-label={studio.agentName() + " is working: stop"} width={28} height={28} borderRadius={8}
						background={c("hair2")} alignItems="center" justifyContent="center" cursor="pointer" onPress={() -> studio.stopTurn()}>
						<view tag="chat-working" width={10} height={10} borderRadius={5} background={Color.parse(studio.agentColour())}
							ref={(n:Node) -> Watch.pulse(n, () -> working(studio))}/>
					</button>
				</Show>
			</view>
		</view>;
	}

	// what the prompt is sent about (AcpAgent.blocks: the frame's name and its
	// PNG): the frame, its picture; × sends it about the whole app, the frame
	// still selected
	static function about(studio:Studio, name:String):View {
		var s = studio.previews?.screen(name), p = SelectionBar.parts(studio.project, name);
		return <view tag="about-chip" flexDirection="row" alignItems="center" columnGap={6} alignSelf="flex-start" maxWidth="100%" height={24}
			padding="0 4 0 4" borderRadius={Theme.CHIP} background={c("bubble")}>
			<Show when={s?.image() != null}>
				<image tag="about-image" src={s?.image()} height={16} width={16 * (s == null ? 1 : s.width() / Math.max(1, s.height()))} borderRadius={2} flexShrink={0}/>
			</Show>
			<text fontSize={11} color={c("ink2")} lineClamp={1} textWrap="nowrap" textOverflow="ellipsis" flexShrink={1} minWidth={0}>{"About: " + (p?.label ?? name)}</text>
			<button tag="about-clear" aria-label="Not about this frame" width={16} height={16} alignItems="center" justifyContent="center" flexShrink={0}
				cursor="pointer" onPress={() -> studio.clearAbout()}>
				<image src={Icons.close} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("ink3")}/>
			</button>
		</view>;
	}

	// the agents found (Agents), the one in use marked; another taken for the next prompt
	static function agents(studio:Studio, menu:helder.view.graph.Signal<Bool>):View
		return <view tag="agent-menu" slot="floating" padding={4} rowGap={2} minWidth={180} boxShadow={Theme.POPOVER}>
			<For each={Agents.found()}>{(id:Read<String>) ->
				<button tag={"agent-" + id()} slot="menu-item" aria-label={Agents.label(id())}
					data-on={Agents.label(id()) == studio.agentName() ? "true" : "false"} onPress={() -> {
						menu(false);
						studio.useAgent(id());
					}}>
					<view width={6} height={6} borderRadius={3} background={Color.parse(Agents.colour(id()))}/>
					<text>{Agents.label(id())}</text>
				</button>
			}</For>
		</view>;
}

// a note or a question card in its place in a turn's reply
private typedef Place = {key:String, at:Int, note:Null<Inbox.Note>, ask:Null<Questions.Question>};
