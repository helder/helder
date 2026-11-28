package helder.ui.fast;

// helder.ui.fast for TypeScript programs (helder.typescript): fast nodes,
// their styles (style({...}): a Style; a CSS module imported is its
// classes' Styles), themes, and <Fast>, the boundary from helder.ui's
// markup. Markup inside <Fast> is fast nodes' (FastRenderer): helder.ui's
// elements and attributes, style={...} a Style.
@:typescript("helder/ui/fast")
@:typescript.classes(helder.ui.fast.Node, helder.ui.fast.TextNode, helder.ui.fast.FieldNode, helder.ui.fast.IconNode, helder.ui.fast.Tree,
	helder.ui.fast.Theme, helder.ui.fast.Style)
@:typescript.functions(Fast = helder.ui.fast.FastTags.Fast, style = helder.ui.fast.Style.ofProps)
@:typescript.imports("helder/ui")
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
