package studio;

import helder.asset.Embed;
import helder.ui.Svg;

// The studio's icons: Lucide's (apps/studio/icons, ISC: LICENSE), only
// those used, embedded; 24 by 24, stroked in the text's colour, drawn at
// 16 or 14 points (Theme.ICON), their strokes Lucide's 2
class Icons {
	// (the studio's own: an agent's pointer on the canvas, filled in its colour)
	public static final pointer = load(Embed.bytes("icons/agent-pointer.svg"));
	public static final appWindow = load(Embed.bytes("icons/app-window.svg"));
	public static final arrowUp = load(Embed.bytes("icons/arrow-up.svg"));
	public static final audioLines = load(Embed.bytes("icons/audio-lines.svg"));
	public static final bookOpen = load(Embed.bytes("icons/book-open.svg"));
	public static final model = load(Embed.bytes("icons/box.svg"));
	public static final chevronDown = load(Embed.bytes("icons/chevron-down.svg"));
	public static final chevronRight = load(Embed.bytes("icons/chevron-right.svg"));
	public static final code = load(Embed.bytes("icons/code.svg"));
	public static final component = load(Embed.bytes("icons/component.svg"));
	public static final file = load(Embed.bytes("icons/file.svg"));
	public static final fileCode = load(Embed.bytes("icons/file-code.svg"));
	public static final folder = load(Embed.bytes("icons/folder.svg"));
	public static final folderOpen = load(Embed.bytes("icons/folder-open.svg"));
	public static final frame = load(Embed.bytes("icons/frame.svg"));
	public static final globe = load(Embed.bytes("icons/globe.svg"));
	public static final image = load(Embed.bytes("icons/image.svg"));
	public static final layoutGrid = load(Embed.bytes("icons/layout-grid.svg"));
	public static final maximize = load(Embed.bytes("icons/maximize.svg"));
	public static final monitor = load(Embed.bytes("icons/monitor.svg"));
	public static final penTool = load(Embed.bytes("icons/pen-tool.svg"));
	public static final pause = load(Embed.bytes("icons/pause.svg"));
	public static final play = load(Embed.bytes("icons/play.svg"));
	public static final redo = load(Embed.bytes("icons/redo-2.svg"));
	public static final repeat = load(Embed.bytes("icons/repeat.svg"));
	public static final ruler = load(Embed.bytes("icons/ruler.svg"));
	public static final scan = load(Embed.bytes("icons/scan.svg"));
	public static final search = load(Embed.bytes("icons/search.svg"));
	public static final smartphone = load(Embed.bytes("icons/smartphone.svg"));
	public static final sparkles = load(Embed.bytes("icons/sparkles.svg"));
	public static final element = load(Embed.bytes("icons/square.svg"));
	public static final font = load(Embed.bytes("icons/type.svg"));
	public static final undo = load(Embed.bytes("icons/undo-2.svg"));
	public static final close = load(Embed.bytes("icons/x.svg"));

	static function load(b:haxe.io.Bytes):Svg
		return Svg.parse(b.toString());
}
