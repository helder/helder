import helder.asset.Embed;
import helder.ui.Svg;

// Lucide's icons (apps/foundry/icons, ISC: LICENSE), those used
class Icons {
	public static final pen = load(Embed.bytes("icons/pen-tool.svg"));
	public static final pointer = load(Embed.bytes("icons/mouse-pointer-2.svg"));
	public static final eraser = load(Embed.bytes("icons/eraser.svg"));
	public static final undo = load(Embed.bytes("icons/undo-2.svg"));
	public static final redo = load(Embed.bytes("icons/redo-2.svg"));
	public static final eye = load(Embed.bytes("icons/eye.svg"));
	public static final download = load(Embed.bytes("icons/download.svg"));
	public static final trash = load(Embed.bytes("icons/trash-2.svg"));
	public static final sparkles = load(Embed.bytes("icons/sparkles.svg"));
	public static final component = load(Embed.bytes("icons/component.svg"));
	public static final scissors = load(Embed.bytes("icons/scissors.svg"));
	public static final down = load(Embed.bytes("icons/chevron-down.svg"));
	public static final right = load(Embed.bytes("icons/chevron-right.svg"));

	static function load(b:haxe.io.Bytes):Svg
		return Svg.parse(b.toString());
}
