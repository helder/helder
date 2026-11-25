package studio;

import helder.gfx.Color;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.ui.widgets.WindowButtons;
import helder.ui.widgets.WindowButtons.WindowControls;
import studio.Theme.c;

// The studio's shell (not --classic): a header (the window's buttons, the
// project's tab, its dot the working agent's colour, pulsing while it
// works; Play), then the chat (Chat) left of the canvas (Board, watched:
// panned, zoomed, a frame aimed at and played, nothing edited), a file's
// code over the canvas' left part (CodePanel). A blank sheet (nothing on
// the canvas, nothing asked yet) is the dots and one prompt in the middle;
// the first prompt moves it into the chat (matched: it flies there) as the
// column slides in.
class Watch implements Markup {
	public static function view(studio:Studio):View
		return <view tag="watch" position="absolute" inset={0} background={c("ground")} color={c("ink")} font-family={Theme.UI} font-size={Theme.BODY}>
			{header(studio)}
			<view direction="row" grow={1} min-height={0}>
				<Show when={!blank(studio) && studio.talk.open()}>{Chat.view(studio)}</Show>
				<view tag="canvas" grow={1} min-width={0}>
					<view position="absolute" inset={0}>{Board.view(studio)}</view>
					<Show when={!studio.classic && !blank(studio) && studio.waiting()}>{blocks(studio)}</Show>
					{CodePanel.view(studio)}
					<Show when={blank(studio)}>
						<view tag="blank" position="absolute" inset={0} align-items="center" justify="center" pointer-events="none">
							<view width={Theme.BLANK} max-width="90%" margin-top={-40} pointer-events="auto">{Chat.input(studio, true)}</view>
						</view>
					</Show>
					<Show when={studio.playing() != null}>
						<view tag="player-card" position="absolute" inset={0} background={c("ground")} transition="fade scale(0.98)" motion="snappy">
							<view grow={1} min-height={0} instant>{Play.view(studio)}</view>
						</view>
					</Show>
				</view>
			</view>
		</view>;

	// (the first frames' places, held: frame-sized blocks shimmering, no
	// caption, until the agent's first change makes them; then they fade as
	// the frames rise into place)
	static inline var BLOCK_W = 210;
	static inline var BLOCK_H = 300;

	static function blocks(studio:Studio):View {
		studio.marks.hold();
		return <view tag="queued" position="absolute" inset={0} direction="row" align-items="center" justify="center" column-gap={24} pointer-events="none"
			transition="fade">
			<For each={[0, 1, 2]}>{(k:Read<Int>) ->
				<view tag={"queued-" + k()} width={BLOCK_W} height={BLOCK_H} radius={Theme.CARD} overflow="hidden" shrink={0} background={c("skeleton")}>
					<For each={[for (j in 0...STRIPES) j]}>{(j:Read<Int>) ->
						<view position="absolute" top={0} bottom={0} width={SWEEP / STRIPES + 1} left={sweep(studio) + j() * SWEEP / STRIPES}
							background={c("shimmer")} opacity={1 - Math.abs((j() + 0.5) / STRIPES * 2 - 1)}/>
					}</For>
				</view>
			}</For>
		</view>;
	}

	// (the shimmer: a band SWEEP wide, the queued frames' 1.6 s sweep, of solid
	// stripes rising to #25252b and back, so that the blocks' corners clip it)
	static inline var SWEEP = 260;
	static inline var STRIPES = 26;

	static function sweep(studio:Studio):Float
		return ((studio.marks.time() / 1.6) % 1) * (BLOCK_W + SWEEP) - SWEEP;

	// a blank sheet: nothing on the canvas, nothing asked yet
	public static function blank(studio:Studio):Bool
		return studio.talk.turns().length == 0 && (studio.layout.screens().length == 0 || studio.starter);

	static function header(studio:Studio):View
		return <view tag="header" drag-region height={Theme.HEADER} shrink={0} direction="row" align-items="center" column-gap={8}
			padding={'0 ${WindowButtons.side() == "end" ? 0 : 12} 0 12'} border-width="0 0 1 0" border-color={c("hair")}>
			<Show when={WindowButtons.side() == "start"}><WindowControls/></Show>
			<view tag="tab" direction="row" align-items="center" column-gap={8} height={28} padding="0 12" radius={7} background={c("tab")}>
				<view tag="tab-dot" width={6} height={6} radius={3} background={Color.parse(dot(studio))} ref={(n:Node) -> pulse(n, () -> busy(studio))}
					outline-width={studio.talk.questions() > 0 ? 1.5 : 0} outline-offset={1.5} outline-color={Color.parse(dot(studio))}/>
				<text font-size={Theme.CHAT_SIZE} max-lines={1}>{studio.project?.name ?? "helder studio"}</text>
			</view>
			<view grow={1}/>
			<Show when={playable(studio)}>{play(studio)}</Show>
			<Show when={WindowButtons.side() == "end"}><WindowControls side="end"/></Show>
		</view>;

	// (a frame to play: not on the blank sheet, nor while the first frames' places are held)
	static function playable(studio:Studio):Bool
		return studio.layout.screens().length > 0 && !blank(studio) && !studio.waiting();

	// Play: the frame aimed at, else the app (Studio.play), in the canvas' place
	static function play(studio:Studio):View
		return <view:button tag="play" role="button" label={studio.playing() == null ? "Play" : "Stop"} focusable direction="row" align-items="center"
				column-gap={6} height={28} padding="0 12" radius={8} background={c("ink")} color={c("ground")} cursor="pointer"
				onPress={() -> if (studio.playing.peek() != null) studio.stopPlay() else studio.play()}>
				<image src={studio.playing() == null ? Icons.play : Icons.element} width={Theme.ICON_XS} height={Theme.ICON_XS}/>
				<text font-size={12} font-weight={Theme.MEDIUM}>{studio.playing() == null ? "Play" : "Stop"}</text>
			</view:button>;

	// (an agent works: the prompt's turn runs, or one over MCP says it does;
	// a question for the user holds the dot still, ringed)
	static function busy(studio:Studio):Bool
		return studio.talk.questions() == 0 && (Chat.working(studio) || Lambda.exists(studio.presence.peers(), p -> p.working));

	// (the tab's dot: the working agent's colour, the prompt's agent's when none works)
	static function dot(studio:Studio):String {
		if (studio.talk.waits()) return Chat.waiter(studio).colour;
		if (Chat.working(studio)) return studio.agentColour();
		var p = Lambda.find(studio.presence.peers(), p -> p.working);
		return p != null ? p.colour : studio.agentColour();
	}

	// a node's opacity breathing while on() (1.4 s), still otherwise
	public static function pulse(n:Node, on:Void->Bool) {
		var running = false;
		effect(() -> on(), (yes:Bool) -> {
			if (!yes || running) return;
			running = true;
			Clock.addFor(n, now -> {
				var still = !on();
				n.style.opacity = still ? 1 : 0.35 + 0.65 * (0.5 - 0.5 * Math.cos(now / 1.4 * Math.PI * 2));
				if (still) running = false;
				return !still;
			});
		});
	}
}
