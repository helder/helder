import helder.gfx.Color;
import helder.ui.Dim;
import helder.ui.DimValue;
import helder.ui.Node;
import helder.ui.fast.Style;
import helder.ui.fast.Style.StyleProps;

// A helder.ui node's look as a fast node's style (the bench's fast
// variant): its own fields typed as they are, what it inherits where it
// says it, its look hovered as a hover variant. The mirror the cascade
// variants read, but no CSS in between.
class FastMirror {
	public static function props(n:Node, hover:Null<StyleProps>):StyleProps {
		var s = n.style, f = n.font();
		var zero = helder.os.Edges.ZERO;
		var p:helder.os.Edges = s.padding ?? zero, g:helder.os.Edges = s.margin ?? zero, b = s.borderEdges ?? zero;
		inline function edges(e:helder.os.Edges):Array<Float>
			return [e.top, e.right, e.bottom, e.left].map(v -> Math.isNaN(v) ? 0.0 : v);
		var out:StyleProps = {
			display: s.display,
			flexDirection: s.flexDirection,
			flexWrap: s.flexWrap ? true : null,
			position: s.position,
			justifyContent: s.justifyContent,
			alignItems: s.alignItems,
			alignSelf: s.alignSelf == Auto ? null : s.alignSelf,
			flexGrow: s.flexGrow == 0 ? null : s.flexGrow,
			flexShrink: s.flexShrink == 1 ? null : s.flexShrink,
			flexBasis: size(s.flexBasis),
			width: size(s.width),
			height: size(s.height),
			minWidth: size(s.minWidth),
			minHeight: size(s.minHeight),
			maxWidth: size(s.maxWidth),
			maxHeight: size(s.maxHeight),
			padding: edges(p),
			margin: edges(g),
			borderWidth: edges(b),
			borderColor: s.borderColor.a > 0 ? (s.borderColor : Int) : null,
			borderRadius: s.borderRadius > 0 ? s.borderRadius : null,
			rowGap: s.rowGap == 0 ? null : s.rowGap,
			columnGap: s.columnGap == 0 ? null : s.columnGap,
			overflow: s.overflowY != Visible ? s.overflowY : s.overflowX != Visible ? s.overflowX : null,
			opacity: s.opacity < 1 ? s.opacity : null,
			background: s.background.a > 0 ? (s.background : Int) : null,
			color: n.parent == null || n.textColor() != n.parent.textColor() ? (n.textColor() : Int) : null,
			fontFamily: s.fontFamily,
			fontSize: s.fontSize,
			fontWeight: s.fontWeight,
			lineHeight: s.lineHeightPx != null ? s.lineHeightPx / f.size : s.lineHeight,
			textAlign: s.textAlign,
			wrap: s.textWrap == null ? null : s.textWrap != NoWrap,
			textOverflow: s.textOverflow == Clip ? null : s.textOverflow,
			lineClamp: s.lineClamp == 0 ? null : s.lineClamp,
			hover: hover
		};
		return out;
	}

	// (its look hovered: what changed of its background, text colour and border colour)
	public static function hovered(ui:helder.ui.Ui, n:Node):Null<StyleProps> {
		if (n.slot == null) return null;
		var s = n.style, bg = s.background, fg = n.textColor(), bc = s.borderColor;
		@:privateAccess n.setState(true, false, false);
		ui.update();
		var out:StyleProps = {};
		var any = false;
		if (s.background != bg) {
			out.background = (s.background : Int);
			any = true;
		}
		if (n.textColor() != fg) {
			out.color = (n.textColor() : Int);
			any = true;
		}
		if (s.borderColor != bc) {
			out.borderColor = (s.borderColor : Int);
			any = true;
		}
		@:privateAccess n.setState(false, false, false);
		ui.update();
		return any ? out : null;
	}

	static function size(d:Dim):Null<Size>
		return switch (d : DimValue) {
			case Px(v): v;
			case Percent(v): helder.ui.box.Len.Percent(v);
			case _: null;
		}
}
