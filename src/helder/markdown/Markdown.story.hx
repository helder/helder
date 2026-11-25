package helder.markdown;

import helder.story.Story;
import helder.ui.TextSelection;
import helder.view.*;
import helder.view.graph.Graph.*;

// A MarkdownView's text selected as one document: from its first
// paragraph's second word through its list into its code block
final selected = story({
	name: "Markdown/selected across blocks",
	width: 600,
	height: 520,
	render: c -> {
		var v = new MarkdownView({doc: Markdown.parse(SAMPLE)});
		onSettled(() -> {
			var p = v.find("markdown-p"), code = v.find("code-view");
			if (v.ui != null && p != null && code != null) v.ui.selectText(TextSelection.between(v, p, 4, code, 12));
		});
		<view grow={1}>{v}</view>;
	}
});

private final SAMPLE = "# Selecting text\n\nThe whole document is **one selection**: a drag runs from a paragraph into the next, through [links](#), lists and code.\n\n- a list item\n- another, *emphasised*\n\n```ts\nconst text = selection.text()\n```\n\nCopied with a blank line between blocks.\n";
