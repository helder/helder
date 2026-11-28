package helder.ui.view;

import helder.test.Test;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.TextNode;
import helder.ui.Ui;
import helder.ui.access.AccessTree;
import helder.ui.access.Role;
import helder.view.Render;
import helder.view.View;

// HTML's names as ui's elements (helder.view.Vocabulary): what each is
// natively, to the keyboard and to assistive technology; ARIA's attributes
// the node's Semantics; hidden not rendered
function tests() {
	function mount(v:View):{ui:Ui, dispose:Void->Void} {
		var ui = new Ui(new helder.story.StoryText(), 320, 200);
		var dispose = Render.render(v, ui.root);
		ui.update();
		return {ui: ui, dispose: dispose};
	}
	function access(ui:Ui, n:Node)
		return @:privateAccess AccessTree.build(ui).nodes.get(n.accessId);

	describe("Elements", () -> {
		test("a button: a Button, focusable, pressed by Enter and Space", () -> {
			var pressed = 0;
			var m = mount(Fixture.button(() -> pressed++));
			var b = m.ui.root.find("save");
			equals(b.tag, "save");
			equals(b.semantics.role, Role.Button);
			equals(b.focusable, true);
			m.ui.setFocus(b);
			m.ui.keyDown(Key.ENTER, 0);
			m.ui.keyDown(Key.SPACE, 0);
			equals(pressed, 2);
			equals(access(m.ui, b).role, Role.Button);
			m.dispose();
		});
		test("an explicit role wins over the element's", () -> {
			var m = mount(Fixture.tab());
			equals(m.ui.root.find("tab").semantics.role, Role.Tab);
			m.dispose();
		});
		test("a link, a heading's level, a list's items", () -> {
			var m = mount(Fixture.document());
			var a = m.ui.root.find("link"), h = m.ui.root.find("title"), li = m.ui.root.find("item");
			equals(a.semantics.role, Role.Link);
			equals(a.semantics.href, "https://helder.build");
			equals([h.semantics.role, h.semantics.level], [Role.Heading, 2]);
			equals(h.style == helder.ui.controls.Look.base.part("h2"), true);
			equals(Std.isOfType(h, TextNode), true);
			equals(m.ui.root.find("list").semantics.role, Role.List);
			equals(li.semantics.role, Role.ListItem);
			m.dispose();
		});
		test("landmarks", () -> {
			var m = mount(Fixture.landmarks());
			var roles = [for (t in ["nav", "main", "header", "footer", "aside", "section", "form", "article"]) m.ui.root.find(t).semantics.role];
			equals(roles, [Role.Navigation, Role.Main, Role.Banner, Role.ContentInfo, Role.Complementary, Role.Region, Role.Form, Role.Article]);
			equals([for (r in roles) r.aria()], ["navigation", "main", "banner", "contentinfo", "complementary", "region", "form", "article"]);
			m.dispose();
		});
		test("ARIA's attributes are the node's Semantics, and a theme's states", () -> {
			var m = mount(Fixture.aria());
			var s = m.ui.root.find("slider");
			equals(s.semantics.label, "Volume");
			equals([s.semantics.valueNow, s.semantics.valueMin, s.semantics.valueMax], [3.0, 0.0, 10.0]);
			equals(s.semantics.expanded, true);
			equals([s.semantics.posInSet, s.semantics.setSize], [2, 5]);
			equals(s.attr("aria-expanded"), "true");
			equals(m.ui.root.find("decor").semantics.hidden, true);
			m.dispose();
		});
		test("hidden: not rendered", () -> {
			var m = mount(Fixture.hidden());
			var n = m.ui.root.find("gone");
			equals(n.used.none, true);
			// (no place in the layout: the next one where it would be)
			equals(m.ui.root.find("next").x, 0.0);
			m.dispose();
		});
	});
}

private class Fixture implements helder.view.Markup {
	public static function button(press:Void->Void):View
		return <view><button tag="save" onPress={press}>Save</button></view>;

	public static function tab():View
		return <button tag="tab" role="tab">One</button>;

	public static function document():View
		return <article tag="doc">
			<h2 tag="title">Title</h2>
			<p>Read <a tag="link" href="https://helder.build">helder</a> and <strong>more</strong>.</p>
			<ul tag="list"><li tag="item"><text>One</text></li></ul>
		</article>;

	public static function landmarks():View
		return <view>
			<nav tag="nav"/><main tag="main"/><header tag="header"/><footer tag="footer"/>
			<aside tag="aside"/><section tag="section"/><form tag="form"/><article tag="article"/>
		</view>;

	public static function aria():View
		return <view>
			<view tag="slider" role="slider" aria-label="Volume" aria-valuenow={3} aria-valuemin={0} aria-valuemax={10} aria-expanded aria-posinset={2}
				aria-setsize={5}/>
			<image tag="decor" aria-hidden/>
		</view>;

	public static function hidden():View
		return <view flexDirection="row"><view tag="gone" width={50} height={10} hidden/><view tag="next" width={20} height={10}/></view>;
}
