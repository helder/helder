package studio;

import haxe.CallStack;
import helder.view.*;
import helder.view.Flow.*;
import studio.Theme.c;

using StringTools;

// The studio's own error that nothing caught (an event's or a frame's,
// helder.os.App.onError; a view's making, Errored): shown over the studio,
// which goes on without what threw, with where it was thrown and how it
// got there (hxmc's stacks, natively); Reload makes the studio's view
// again (Studio.reload), the project and its previews kept. In the browser
// the module has no stacks of its own (no frame records in WebAssembly):
// an error out of an event ends it, and the page shows its frames instead
// (studio.mjs's crashed).
@:renderer(helder.ui.view.NodeRenderer)
class Crash implements Markup {
	public final message:String;
	// the file and line it was thrown at ("" when unknown)
	public final where:String;
	public final stack:String;

	function new(message, where, stack) {
		this.message = message;
		this.where = where;
		this.stack = stack;
	}

	public static function of(e:Dynamic):Crash {
		if (!(e is haxe.Exception)) return new Crash(Std.string(e), "", "");
		var x:haxe.Exception = e, items = x.stack.asArray();
		var where = "";
		for (i in items) switch i {
			case FilePos(_, file, line, _):
				where = '$file:$line';
				break;
			case _:
		}
		return new Crash(x.message, where, CallStack.toString(x.stack).trim());
	}

	public static function view(studio:Studio, crash:Crash, reload:Void->Void):View
		return <view tag="crash-layer" slot="floating" position="absolute" inset={0} alignItems="center" justifyContent="center" padding={16}
			background="rgba(11,11,13,0.72)">
			<view tag="crash" role="alertdialog" aria-label="The studio stopped" width={560} maxWidth="100%" maxHeight="100%" padding={16} rowGap={10}
				background={c("bg")} borderRadius={Theme.RADIUS_M} boxShadow={Theme.POPOVER} borderWidth={1} borderColor={c("line")}>
				<text fontSize={13} fontWeight={Theme.MEDIUM}>The studio stopped what it was doing</text>
				<text color={c("red")}>{crash.message}</text>
				<Show when={crash.where != ""}>
					<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} color={c("fg2")}>{crash.where}</text>
				</Show>
				<Show when={crash.stack != ""}>
					<scroll maxHeight={240} minHeight={0} padding={8} borderRadius={Theme.RADIUS} background={c("canvas")}>
						<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} color={c("fg3")}>{crash.stack}</text>
					</scroll>
				</Show>
				<view flexDirection="row" justifyContent="end" columnGap={8}>
					<button tag="crash-reload" slot="primary" aria-label="Reload" onPress={reload}>
						<text>Reload</text>
					</button>
				</view>
			</view>
		</view>;
}
