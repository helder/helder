package studio;

import helder.gfx.Color;
import helder.markdown.Markdown;
import helder.markdown.MarkdownView;
import helder.ui.*;
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
// while it thinks, its last tools as lines (the ones before folded), a
// failed build's row, its question as a card, what the user said while it
// worked (the inbox's notes: "sent while working", then "seen"); at the
// bottom the questions waiting, what it is doing (Stop while it works) and
// the input, with the agent's chip and its menu. Every input of the
// studio's is here: the canvas is to watch.
class Chat implements Markup {
	public static function view(studio:Studio):View
		return <view tag="chat" width={Theme.CHAT} shrink={0} background={c("chat")} border-width="0 1 0 0" border-color={c("hair")} min-height={0}
			transition="fade slide-left(24)">
			<scroll tag="chat-log" grow={1} min-height={0} padding="18 18 8" row-gap={14} font-size={Theme.CHAT_SIZE} color={c("ink2")}
				ref={(n:Node) -> log = n}>
				<For each={[for (i in 0...studio.talk.turns().length) i]}>{(i:Read<Int>) -> turn(studio, i())}</For>
				<For each={studio.marks.changes().filter(c -> c.turn < 0)} by={(c:Marks.Changed) -> c.id}>{(c:Read<Marks.Changed>) -> change(studio, c)}</For>
				<For each={studio.questions.all().filter(q -> q.turn < 0)} by={(q:Questions.Question) -> q.id}>{(q:Read<Questions.Question>) -> Asks.card(studio, q)}</For>
			</scroll>
			<view padding="12 14 14" row-gap={8} shrink={0}>
				<Show when={studio.talk.questions() > 0}>
					<view:button tag="chat-questions" role="button" label="The questions for you" direction="row" align-items="center" column-gap={6}
						cursor="pointer" color={c("ink3")} onPress={() -> if (log != null) log.scrollY = 1e9}>
						<view width={6} height={6} radius={3} background={Color.parse(studio.agentColour())}/>
						<text font-size={12}>{questions(studio.talk.questions())}</text>
					</view:button>
				</Show>
				<Show when={working(studio) || studio.talk.waits()}>{status(studio)}</Show>
				{input(studio, false)}
			</view>
		</view>;

	// (the chat's scroller: the questions' strip scrolls it to them, at its end)
	static var log:Null<Node> = null;

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

	// a turn: the prompt, then the agent's part
	static function turn(studio:Studio, i:Int):View {
		function t():Turn {
			var all = studio.talk.turns();
			return i < all.length ? all[i] : Turns.start("");
		}
		var steps = signal(false), tools = signal(false);
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
			{reply(studio, t)}
			<Show when={Turns.running(t()) && t().thought != "" && t().text == ""}>
				<text tag="chat-thinking" color={c("dim")} font-size={12}>Thinking…</text>
			</Show>
			<Show when={t().tools.length > 0}>
				<view tag="chat-tools" row-gap={4} font-family={Theme.CODE} font-size={Theme.SMALL} color={c("ink3")}>
					<Show when={Replies.tools(t().tools, tools()).folded > 0}>
						<text tag="chat-tools-folded" font-family={Theme.UI} font-size={12} cursor="pointer" onClick={_ -> tools(true)}>{
							'Made ${Replies.tools(t().tools, false).folded} changes ▸'
						}</text>
					</Show>
					<For each={Replies.tools(t().tools, tools()).shown} by={(x:{id:String, title:String, kind:String, status:String}) -> x.id}>{
						(x:Read<{id:String, title:String, kind:String, status:String}>) ->
						<view tag={"chat-tool-" + x().id} direction="row" column-gap={6}
							color={x().status == "failed" ? c("red") : x().status != "completed" && Turns.running(t()) ? Color.parse(studio.agentColour()) : c("ink3")}>
							<text shrink={0}>{Turns.running(t()) || x().status == "completed" || x().status == "failed" ? Replies.mark(x().status) : "·"}</text>
							<text grow={1} min-width={0} max-lines={1} text-overflow="ellipsis">{x().title}</text>
						</view>
					}</For>
				</view>
			</Show>
			<Show when={t().build != null || t().error != null}>{failure(studio, t)}</Show>
			<For each={studio.marks.changes().filter(c -> c.turn == i)} by={(c:Marks.Changed) -> c.id}>{(c:Read<Marks.Changed>) -> change(studio, c)}</For>
			<Show when={t().ask != null}>{card(studio, t)}</Show>
			<For each={studio.questions.all().filter(q -> q.turn == i)} by={(q:Questions.Question) -> q.id}>{(q:Read<Questions.Question>) -> Asks.card(studio, q)}</For>
			<For each={studio.inbox.notes().filter(n -> n.turn == i && n.kind == "direction")} by={(n:Inbox.Note) -> n.id}>{(n:Read<Inbox.Note>) -> note(n)}</For>
		</view>;
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
	static function reply(studio:Studio, t:Void->Turn):MarkdownView {
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
		effect(() -> t().text, text -> v.update(Replies.parse(text, dir, f -> Files.exists(f) && !Files.isDirectory(f))));
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

	// the agent's question (a permission, studio.ask's): its options as
	// buttons, "Something else…" the input; answered here alone
	static function card(studio:Studio, t:Void->Turn):View
		return <view tag="chat-card" row-gap={10} padding={12} radius={Theme.CARD} background={c("card")} border-width={1} border-color={c("hair2")}
			shadow="0 4 16 rgba(0,0,0,0.35)">
			<view direction="row" column-gap={8} align-items="flex-start">
				<text grow={1} min-width={0} color={c("ink")} font-size={Theme.CHAT_SIZE}>{t().ask?.question ?? ""}</text>
				<view tag="chat-card-dot" width={6} height={6} radius={3} margin-top={6} background={Color.parse(studio.agentColour())}/>
			</view>
			<view direction="row" wrap={true} gap={6}>
				<For each={[for (i => o in t().ask?.options ?? []) {i: i, name: o}]}>{(o:Read<{i:Int, name:String}>) ->
					<view:button tag={"card-option-" + o().i} role="button" label={o().name} focusable height={28} padding="0 10" radius={8}
						background={c("bubble")} color={c("ink")} justify="center" cursor="pointer" onPress={() -> studio.answer(o().i)}>
						<text font-size={12}>{o().name}</text>
					</view:button>
				}</For>
				<view:button tag="card-else" role="button" label="Something else" focusable height={28} padding="0 10" radius={8} justify="center"
					color={c("ink3")} cursor="pointer" onPress={() -> if (studio.talk.field != null) studio.talk.field.focus()}>
					<text font-size={12}>Something else…</text>
				</view:button>
			</view>
		</view>;

	// what the agent does: working (Stop), or waiting for the user
	static function status(studio:Studio):View
		return <view tag="chat-status" direction="row" align-items="center" column-gap={8} font-size={12} color={c("ink3")}>
			<view width={8} height={8} radius={4} background={Color.parse(studio.agentColour())}/>
			<text grow={1}>{studio.agentName() + (studio.talk.waits() ? " waits for you" : " is working")}</text>
			<Show when={working(studio)}>
				<view:button tag="chat-stop" role="button" label="Stop" focusable height={24} padding="0 10" radius={Theme.CHIP} background={c("bubble")}
					color={c("ink2")} justify="center" cursor="pointer" onPress={() -> studio.stopTurn()}>
					<text font-size={12}>Stop</text>
				</view:button>
			</Show>
		</view>;

	// the input: the prompt (blank: the sheet's first, bigger), the agent's
	// chip (its menu: the agents found), send; Enter sends (while the agent
	// works: steering, the next prompt). Glows in the agent's colour while it
	// waits for the user.
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
			border-color={studio.talk.waits() ? Color.parse(studio.agentColour()) : c(blank ? "hair" : "hair2")}
			shadow={blank ? "0 24 80 rgba(0,0,0,0.35)" : "none"}>
			<field tag="prompt" slot="ask-input" label="Prompt" value={text} min-height={blank ? 48 : 22} font-size={blank ? 16 : Theme.CHAT_SIZE}
				placeholder={blank ? "What do you want to make?" : working(studio) ? "Steer while it works…" : "Reply…"} ref={(n:Node) -> studio.talk.field = n}
				onInput={e -> text(e.text)} onKeyDown={e -> if (e.key == Key.ENTER) send()}/>
			<view direction="row" align-items="center" column-gap={8}>
				<view:button tag="agent-chip" role="button" label={"The agent: " + studio.agentName()} focusable direction="row" align-items="center"
					column-gap={6} height={blank ? 28 : 22} padding="0 8" radius={Theme.CHIP} background={c("bubble")} color={c("ink2")} cursor="pointer"
					onPress={() -> menu(!menu.peek())}>
					<view width={blank ? 8 : 6} height={blank ? 8 : 6} radius={4} background={Color.parse(studio.agentColour())}/>
					<text font-size={blank ? 12 : 11}>{studio.agentName()}</text>
					<image src={Icons.chevronDown} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("ink3")}/>
				</view:button>
				<view grow={1}/>
				<view:button tag="send" role="button" label="Send" focusable width={blank ? 32 : 28} height={blank ? 32 : 28} radius={8}
					background={text() == "" ? c("hair2") : c("ink")} color={text() == "" ? c("ink3") : c("ground")} align-items="center" justify="center"
					cursor="pointer" onPress={send}>
					<image src={Icons.arrowUp} width={Theme.ICON_S} height={Theme.ICON_S}/>
				</view:button>
			</view>
			<Show when={menu()}>{agents(studio, menu)}</Show>
		</view>;
	}

	// the agents found (Agents), the one in use marked; another taken for the next prompt
	static function agents(studio:Studio, menu:helder.view.graph.Signal<Bool>):View
		return <view tag="agent-menu" slot="floating" padding={4} row-gap={2} align-self="flex-start" min-width={180}>
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
