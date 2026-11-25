package helder.markdown;

// helder.markdown for TypeScript programs (helder.typescript): Markdown.parse
// (a Doc: its blocks are Haxe's enums, given to MarkdownView as they are),
// slug, and MarkdownView, a document as nodes in helder/ui's tree.
@:typescript("helder/markdown")
@:typescript.classes(helder.markdown.Markdown, helder.markdown.MarkdownView)
@:typescript.types(helder.markdown.Doc, helder.markdown.MarkdownView.MarkdownProps)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
