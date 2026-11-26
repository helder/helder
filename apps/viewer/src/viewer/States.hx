package viewer;

import helder.ui.Clock;
import helder.ui.Transform;
import helder.ui.controls.Look;
import helder.ui.controls.Standard;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// Why the folder shows nothing, in its place: empty (a dashed outline),
// still reading after a moment (rows of skeleton), unreadable (why, and
// Try again), no results for the search; and the spinner that turns while
// a folder is read.
@:renderer(helder.ui.view.NodeRenderer)
class States implements Markup {
	public static function empty(x:Explorer):View
		return <view tag="empty" position="absolute" inset={14} top={44} borderRadius={12} borderWidth={1.5} borderStyle="dashed" borderColor={Look.ref.edge}
			alignItems="center" justifyContent="center" rowGap={8} padding="0 40" pointerEvents="none">
			<image src={Glyphs.get("folder")} width={40} height={40} color={Look.ref.fg3}/>
			<text tag="state-title" fontSize={15} fontWeight={600} marginTop={6}>This folder is empty</text>
			<text fontSize={12.5} color={Look.ref.fg3} textAlign="center" maxWidth={360}>Its images, videos and PDFs show up here as they are added.</text>
		</view>;

	public static function error(x:Explorer):View {
		var b = x.browser;
		function title():String {
			var name = x.sidebar.title(b.dir());
			return switch b.error() {
				case "missing": 'There is no folder “$name”';
				case "notfolder": '“$name” is not a folder';
				case _: 'Viewer can’t open “$name”';
			}
		}
		function why():String
			return switch b.error() {
				case "missing": "It may have been moved, renamed or deleted, or its drive may be disconnected.";
				case "notfolder": "It is a file. Open its folder to see it there.";
				case _: Sys.systemName() == "Mac" ? "macOS keeps this folder private. Allow Full Disk Access for Viewer in System Settings, or choose the folder in the Open dialog to grant it once." :
					"You may not have permission to see its contents.";
			}
		return <view tag="error" position="absolute" inset={0} alignItems="center" justifyContent="center" rowGap={8} padding="0 40">
			<view width={44} height={44} borderRadius={12} background={Look.ref.fill} alignItems="center" justifyContent="center" color={Look.ref.fg2}>
				<image src={Glyphs.get(b.error() == "denied" ? "lock" : "folder")} width={18} height={18}/>
			</view>
			<text tag="state-title" fontSize={15} fontWeight={600} marginTop={6} textAlign="center">{title}</text>
			<text fontSize={12.5} color={Look.ref.fg3} textAlign="center" maxWidth={360}>{why}</text>
			<view flexDirection="row" columnGap={6} paddingTop={10}>
				<Standard.Button tag="retry" onPress={() -> b.reload()}>Try again</Standard.Button>
				<Show when={Browser.parent(b.dir()) != null}>
					<Standard.Button variant="primary" onPress={() -> b.up()}>Enclosing Folder</Standard.Button>
				</Show>
			</view>
		</view>;
	}

	public static function noResults(x:Explorer):View {
		var b = x.browser;
		return <view tag="no-results" position="absolute" inset={0} top={30} alignItems="center" justifyContent="center" rowGap={8} padding="0 40"
			pointerEvents="none">
			<image src={Glyphs.get("search")} width={36} height={36} color={Look.ref.fg3}/>
			<text tag="state-title" fontSize={15} fontWeight={600} marginTop={6} textAlign="center">{() -> 'No results for “${b.query()}” in ${x.sidebar.title(b.dir())}'}</text>
			<text fontSize={12.5} color={Look.ref.fg3} textAlign="center">Search looks at the names in this folder.</text>
		</view>;
	}

	// (rows of skeleton fading out, where the list will be)
	public static function slow(x:Explorer):View
		return <view tag="slow" position="absolute" inset={0} top={30} paddingTop={8} pointerEvents="none" background={Look.ref.surface}>
			{[for (i in 0...6) <view flexDirection="row" alignItems="center" columnGap={10} height={30} padding="0 16" opacity={i < 4 ? 1 : i == 4 ? 0.6 : 0.35}>
				<view width={20} height={15} borderRadius={3} background={Look.ref.fill}/>
				<view width={[220, 180, 240, 160, 200, 210][i]} height={8} borderRadius={4} background={Look.ref.fill}/>
				<view flexGrow={1}/>
				<view width={90} height={8} borderRadius={4} background={Look.ref.fill}/>
				<view width={50} height={8} borderRadius={4} background={Look.ref.fill}/>
			</view>]}
		</view>;

	// a ring's arc, turning while it is shown
	public static function spinner(size:Float):View {
		var angle = signal(0.0), alive = true;
		onCleanup(() -> alive = false);
		Clock.add(t -> {
			angle(t * 450 % 360);
			alive;
		});
		return <image src={Glyphs.get("spin")} width={size} height={size} transform={() -> Transform.rotate(angle())} flexShrink={0}/>;
	}
}
