package studio;

import helder.markdown.Markdown;
import helder.markdown.MarkdownView;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Theme.c;
import studio.Turn;

// The prompt bar under the canvas: what it asks about follows what is in
// focus ("Ask about the whole app…", "Ask about Hangar…"); a prompt goes
// to the studio's agent (Agent: the user's own over ACP, else the studio's
// tools alone). Above it the turn (Studio.turn): the reply as it streams,
// the tools called, the plan, the agent's question as buttons; Stop while
// it runs. Plain on purpose: the redesign restyles it from the same signal.
class Prompt implements Markup {
	public static function view(studio:Studio):View {
		var text = signal("");
		function send() {
			studio.ask(text.peek());
			text("");
		}
		return <view tag="ask-area" position="absolute" bottom={Theme.PAD} left={left(studio)} width={width(studio)} row-gap={6}
			onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<Show when={studio.turn() != null}>
				<view tag="turn" slot="floating" padding="8 10">{transcript(studio)}</view>
			</Show>
			<view tag="ask" slot="floating" direction="row" align-items="center" column-gap={8} height={34} padding="0 10">
				<image src={Icons.sparkles} width={Theme.ICON_S} height={Theme.ICON_S} color={c("accent-ink")}/>
				<field tag="prompt" slot="ask-input" label="Prompt" value={text} placeholder={studio.context().label} onInput={e -> text(e.text)}
					onKeyDown={e -> if (e.key == Key.ENTER) send()}/>
				<Show when={Turns.running(studio.turn())}>
					<view:button tag="ask-stop" slot="button" role="button" label="Stop" onPress={() -> studio.stopTurn()}>
						<text font-size={Theme.SMALL}>Stop</text>
					</view:button>
				</Show>
				<Show when={studio.turn() != null && !Turns.running(studio.turn())}>
					<view:button tag="ask-clear" slot="button" role="button" label="Clear" onPress={() -> studio.clearTurn()}>
						<text font-size={Theme.SMALL}>Clear</text>
					</view:button>
				</Show>
			</view>
		</view>;
	}

	// the turn: what failed and its question first, its plan, its last
	// tools, its text (the compact sheet's too)
	public static function transcript(studio:Studio):View {
		function turn():Turn
			return studio.turn() ?? Turns.start("");
		return <scroll tag="turn-log" max-height={260} min-height={0} row-gap={4}>
			<Show when={turn().build != null}>
				<text tag="turn-build" color={c("red")} font-size={Theme.SMALL}>{"The build failed: " + (turn().build ?? "")}</text>
			</Show>
			<Show when={turn().error != null}>
				<text tag="turn-error" color={c("red")} font-size={Theme.SMALL}>{turn().error ?? ""}</text>
			</Show>
			<Show when={turn().ask != null}>
				<view tag="turn-ask" row-gap={4}>
					<text color={c("fg")} font-size={Theme.SMALL}>{turn().ask?.question ?? ""}</text>
					<view direction="row" column-gap={4}>
						<For each={[for (i => o in turn().ask?.options ?? []) {i: i, name: o}]}>{(o:Read<{i:Int, name:String}>) ->
							<view:button tag={"turn-option-" + o().i} slot="button" role="button" label={o().name} onPress={() -> studio.answer(o().i)}>
								<text font-size={Theme.SMALL}>{o().name}</text>
							</view:button>
						}</For>
					</view>
				</view>
			</Show>
			<For each={turn().steps.map(s -> s)}>{(s:Read<{text:String, done:Bool}>) ->
				<text color={s().done ? c("fg3") : c("fg2")} font-size={Theme.SMALL}>{(s().done ? "✓ " : "○ ") + s().text}</text>
			}</For>
			<For each={turn().tools.slice(-4)} by={(t:{id:String, title:String, kind:String, status:String}) -> t.id}>{(t:Read<{id:String, title:String, kind:String, status:String}>) ->
				<view tag={"turn-tool-" + t().id} direction="row" column-gap={6}>
					<text grow={1} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis" color={c("fg2")} font-size={Theme.SMALL}>{t().title}</text>
					<text color={c("fg3")} font-size={Theme.SMALL}>{t().status}</text>
				</view>
			}</For>
			<Show when={turn().thought != ""}>
				<text tag="turn-thought" color={c("fg3")} font-size={Theme.SMALL} max-lines={3} text-overflow="ellipsis">{turn().thought}</text>
			</Show>
			{reply(studio)}
			<Show when={turn().error == null && turn().text == ""}>
				<text color={c("fg3")} font-size={Theme.SMALL}>{turn().end == null ? "…" : 'ended: ${turn().end}'}</text>
			</Show>
		</scroll>;
	}

	// the reply's text as Markdown, kept as it streams (MarkdownView.update:
	// the blocks before the last stay); its look Theme's markdown-* parts
	static function reply(studio:Studio):MarkdownView {
		var v = new MarkdownView({doc: Markdown.parse(""), scroll: false, codeFont: Theme.CODE, codeSize: Theme.CODE_SIZE, onLink: studio.follow});
		v.tag = "turn-text";
		effect(() -> studio.turn()?.text ?? "", text -> v.update(Markdown.parse(text)));
		return v;
	}

	// (centred between the panels)
	static function width(studio:Studio):Float {
		studio.stageSize();
		var i = studio.insets();
		return Math.min(Theme.ASK, (studio.stageWidth - i.left - i.right) * (studio.compact() ? 0.92 : 0.8));
	}

	static function left(studio:Studio):Float {
		studio.stageSize();
		var i = studio.insets();
		return i.left + (studio.stageWidth - i.left - i.right - width(studio)) / 2;
	}
}
