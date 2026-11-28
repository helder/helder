// title: Mail on fast nodes
// summary: The mail client's three panes on fast nodes: typed styles with hover and selected variants, light and dark theme tokens, no cascade
// tags: ui, view, styles
// demo: canvas 860x560

import helder.os.Settings;
import helder.ui.Key;
import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.ui.fast.FastTags.FastView;
import helder.ui.fast.FastTags.*;
import helder.ui.fast.Style;
import helder.ui.fast.Style.Tint;
import helder.ui.fast.Theme;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// examples/mail's client on fast nodes (helder.ui.fast): the same markup,
// its sheet's slots and states typed Styles with hover and selected
// variants, its light and dark colours a Theme's tokens (dark mode the
// theme's other tone), its actions on the <Fast>. Its nodes are the CSS
// engine's boxes; it links no helder.dom and no cascade.
class MailFast implements Markup {
	public static function declare()
		actions("mailfast", MailFastAction);

	static function main() {
		declare();
		Keymap.global.bind("e", Archive).bind("delete", Delete).bind("secondary-shift-u", MarkUnread);
		UiWindow.run(<Surface title="Mail" width={860} height={560}>{new MailFast().window()}</Surface>);
	}

	// (Mail.sheet's colours: light and dark)
	public static final theme = new Theme([
		"background" => [0xFFFFFFFF, 0xFF09090B], "foreground" => [0xFF18181B, 0xFFFAFAFA], "muted-background" => [0xFFF4F4F5, 0xFF18181B],
		"muted" => [0xFF71717A, 0xFFA1A1AA], "border" => [0xFFE4E4E7, 0xFF27272A], "card" => [0xFFFFFFFF, 0xFF09090B], "hover" => [0xFFF4F4F5, 0xFF27272A],
		"accent" => [0xFFDBEAFE, 0xFF1E3A8A], "accent-foreground" => [0xFF1E3A8A, 0xFFDBEAFE]
	]);

	static inline function t(name:String):Tint
		return Theme.token(name);

	// (Mail.sheet's rules as styles)
	static final body = Style.of({background: t("background"), color: t("foreground"), fontSize: 13});
	static final bar = Style.of({flexDirection: Row, alignItems: Center, columnGap: 8, padding: [8, 12], background: t("muted-background")});
	static final muted = Style.of({color: t("muted")});
	static final rule = Style.of({height: 1, background: t("border")});
	static final panel = Style.of({borderRadius: 8, borderWidth: 1, borderColor: t("border"), background: t("card")});
	static final head = Style.of({flexDirection: Row, columnGap: 8, padding: [6, 10], borderWidth: [0, 0, 1, 0], borderColor: t("border")});
	static final column = Style.of({flexDirection: Row, color: t("muted"), fontWeight: 600, cursor: Pointer, hover: {color: t("foreground")}});
	static final row = Style.of({
		flexDirection: Row,
		columnGap: 8,
		padding: [5, 10],
		cursor: Pointer,
		hover: {background: t("hover")},
		selected: {background: t("accent"), color: t("accent-foreground")}
	});
	static final folderStyle = Style.of({
		flexDirection: Row,
		alignItems: Center,
		borderRadius: 6,
		cursor: Pointer,
		hover: {background: t("hover")},
		selected: {background: t("accent"), color: t("accent-foreground"), fontWeight: 600}
	});
	static final button = Style.of({
		flexDirection: Row,
		alignItems: Center,
		padding: [5, 10],
		borderRadius: 6,
		borderWidth: 1,
		borderColor: t("border"),
		background: t("card"),
		cursor: Pointer,
		hover: {background: t("hover")}
	});
	static final ghost = button.with({borderColor: 0, background: 0});
	static final input = Style.of({
		width: 200,
		padding: [5, 10],
		borderRadius: 6,
		borderWidth: 1,
		borderColor: t("border"),
		background: t("card"),
		focus: {borderColor: t("muted")},
		placeholder: {color: t("muted")}
	});

	public final folders:Array<MailFolder> = [
		{name: "Inbox", level: 0},
		{name: "Receipts", level: 1},
		{name: "Travel", level: 1},
		{name: "Sent", level: 0},
		{name: "Archive", level: 0},
		{name: "Trash", level: 0}
	];
	public final messages:Signal<Array<MailMessage>>;
	public final folder:Signal<MailFolder>;
	public final selected:Signal<Null<MailMessage>> = signal(null);
	public final query = signal("");
	public final sort = signal({by: "date", down: true});
	public final undo:Signal<Null<{text:String, run:Void->Void}>> = signal(null);
	public final dark = signal(Settings.dark.peek());

	public function new() {
		folder = signal(folders[0]);
		messages = signal([
			for (m in MESSAGES)
				new MailMessage(m[0], m[1], m[2], m[3], Std.parseInt(m[4]), m[5] == "unread")
		]);
		effect(() -> selected(), m -> if (m != null) m.unread(false));
	}

	function shown():Array<MailMessage> {
		var f = folder(), q = query().toLowerCase(), s = sort();
		var list = [
			for (m in messages())
				if (m.folder() == f.name && (q == "" || m.subject.toLowerCase().indexOf(q) >= 0 || m.from.toLowerCase().indexOf(q) >= 0))
					m
		];
		list.sort((a, b) -> {
			var c = switch s.by {
				case "from": Reflect.compare(a.from, b.from);
				case "subject": Reflect.compare(a.subject, b.subject);
				case _: a.day - b.day;
			}
			return s.down ? -c : c;
		});
		return list;
	}

	function unread(f:MailFolder):Int {
		var n = 0;
		for (m in messages())
			if (m.folder() == f.name && m.unread()) n++;
		return n;
	}

	function moveTo(name:String) {
		var m = selected.peek();
		if (m == null) return;
		var list = untrack(shown), i = list.indexOf(m), from = m.folder.peek();
		flush(() -> {
			m.folder(name);
			messages(messages.peek().copy());
		});
		var rest = untrack(shown);
		selected(rest.length == 0 ? null : rest[i < rest.length ? i : rest.length - 1]);
		undo({
			text: 'Moved "${m.subject}" to $name',
			run: () -> {
				m.folder(from);
				messages(messages.peek().copy());
				selected(m);
				undo(null);
			}
		});
	}

	function markUnread() {
		var m = selected.peek();
		if (m == null) return;
		m.unread(true);
		selected(null);
	}

	function step(d:Int) {
		var list = untrack(shown);
		if (list.length == 0) return;
		var i = list.indexOf(selected.peek()) + d;
		selected(list[i < 0 ? 0 : i >= list.length ? list.length - 1 : i]);
	}

	function sortBy(by:String) {
		var s = sort.peek();
		sort({by: by, down: s.by == by ? !s.down : by == "date"});
	}

	static function Button(props:{label:String, onPress:Void->Void, ?tag:String, ?variant:String}):FastView
		return <button tag={props.tag ?? "button"} style={props.variant == "ghost" ? ghost : button} onPress={props.onPress}>{props.label}</button>;

	function Column(props:{title:String, by:String, ?width:Float}):FastView
		return <button tag={"sort-" + props.by} style={column} width={props.width} flexGrow={props.width == null ? 1 : 0}
			onPress={() -> sortBy(props.by)}>
			{props.title + (sort().by == props.by ? (sort().down ? " ↓" : " ↑") : "")}
		</button>;

	function cell(m:MailMessage, text:String, ?width:Float):FastView
		return <text width={width} flexGrow={width == null ? 1 : 0} minWidth={0} flexShrink={width == null ? 1 : 0} fontWeight={m.unread() ? 700 : 400}
			textWrap="nowrap" textOverflow="ellipsis">{text}</text>;

	// (in its <Fast>: its theme, light or dark, and its actions)
	public function window():View
		return <Fast theme={dark() ? theme.tone(true) : theme} actions={[Actions.handle(MailFastAction, a -> {
			switch a {
				case Archive: moveTo("Archive");
				case Delete: moveTo("Trash");
				case MarkUnread: markUnread();
			}
			true;
		})]}>{view()}</Fast>;

	public function view():FastView
		return <view style={body} flexGrow={1} minHeight={0}>
			<view style={bar}>
				<text fontWeight={700} fontSize={15} padding="0 8 0 0">Mail</text>
				<Button tag="archive" label="Archive" onPress={() -> moveTo("Archive")}/>
				<Button tag="delete" label="Delete" onPress={() -> moveTo("Trash")}/>
				<Button tag="unread" label="Mark unread" onPress={markUnread}/>
				<view flexGrow={1}/>
				<Button tag="dark" label="Dark mode" variant="ghost" onPress={() -> dark(!dark.peek())}/>
				<field tag="search" style={input} value={query()} placeholder="Search" aria-label="Search messages" onInput={e -> query(e.text)}/>
			</view>
			<view flexDirection="row" flexGrow={1} minHeight={0} columnGap={12} padding={12}>
				<view tag="folders" width={170} flexShrink={0} rowGap={2} role="list" aria-label="Folders">
					<For each={folders}>{(folderOf:Read<MailFolder>) -> {
						var f = folderOf();
						<button style={folderStyle} role="listitem" aria-selected={folder() == f} data-state={folder() == f ? "selected" : null}
							padding={[5, 8, 5, 8 + 16 * f.level]} onPress={() -> {
								folder(f);
								selected(null);
							}}>
							<text flexGrow={1}>{f.name}</text>
							<text style={muted}>{count(unread(f))}</text>
						</button>;
					}}</For>
				</view>
				<view style={panel} width={340} flexShrink={0} minHeight={0}>
					<view style={head}>
						<Column title="From" by="from" width={90}/>
						<Column title="Subject" by="subject"/>
						<Column title="Date" by="date" width={52}/>
					</view>
					<scroll tag="list" flexGrow={1} minHeight={0} focusable role="list" aria-label="Messages" onKeyDown={e -> switch e.key {
						case Key.DOWN:
							step(1);
							e.preventDefault();
						case Key.UP:
							step(-1);
							e.preventDefault();
						case _:
					}}>
						<For each={shown()}>{(message:Read<MailMessage>) -> {
							var m = message();
							<view style={row} role="listitem" aria-selected={selected() == m} data-state={selected() == m ? "selected" : null}
								onPress={() -> selected(m)}>
								{cell(m, m.from, 90)}{cell(m, m.subject)}{cell(m, "Oct " + m.day, 52)}
							</view>;
						}}</For>
						<Show when={shown().length == 0}><text style={muted} padding={12}>No messages</text></Show>
					</scroll>
				</view>
				<view tag="reader" style={panel} flexGrow={1} minWidth={0} padding={16} rowGap={10}>
					<Show when={selected() != null} fallback={<text style={muted}>No message selected</text>}>
						<text tag="reader-subject" fontSize={16} fontWeight={600}>{selected()?.subject}</text>
						<text style={muted}>{selected() == null ? "" : "From " + selected().from + ", October " + selected().day}</text>
						<view style={rule}/>
						<text tag="reader-body" lineHeight={1.5}>{selected()?.body}</text>
					</Show>
				</view>
			</view>
			<Show when={undo() != null}>
				<view style={bar} columnGap={12} padding="6 12" aria-live="polite">
					<text flexGrow={1}>{undo()?.text}</text>
					<Button tag="undo" label="Undo" variant="ghost" onPress={() -> undo.peek()?.run()}/>
					<Button tag="dismiss" label="×" variant="ghost" onPress={() -> undo(null)}/>
				</view>
			</Show>
		</view>;

	static function count(n:Int):String
		return n == 0 ? "" : Std.string(n);

	// from, subject, body, folder, day of October, read or unread (Mail's)
	static final MESSAGES = [
		["Ada", "Draft of the layout chapter", "Here is the chapter on flexbox and grid. The figures are still placeholders; tell me which ones you want redrawn.", "Inbox", "17", "unread"],
		["Grace", "Compiler meeting moved", "The meeting moves to Thursday at ten, same room. Bring the benchmark numbers for the WasmGC build if you have them.", "Inbox", "17", "unread"],
		["Linus", "Re: patch for the scheduler", "Looks fine to me. One nit: the comment above the loop no longer says what it does.", "Inbox", "16", "read"],
		["Margaret", "Launch checklist", "Attached is the checklist for Monday. Every item needs an owner by Friday.", "Inbox", "15", "unread"],
		["Alan", "Lunch?", "There is a new place near the station. Tuesday works for me.", "Inbox", "14", "read"],
		["Barbara", "Notes from the review", "The review went well. The main question was about error messages: they should point at the line that caused them.", "Inbox", "13", "read"],
		["Ken", "Old terminal manuals", "I found a box of manuals from the lab. Do you want any of them before they go to the recycling?", "Inbox", "11", "read"],
		["Bookshop", "Your order has shipped", "Order 4417: two books, shipped today. Expected on Tuesday.", "Receipts", "12", "unread"],
		["Rail", "Your ticket for Brussels", "Coach 6, seat 41. The train leaves at 08:12 from platform 3.", "Travel", "10", "read"],
		["Hotel", "Booking confirmed", "Two nights from the 23rd. Breakfast is included.", "Travel", "9", "read"],
		["Ada", "Re: figures", "I can redraw the grid figures this week.", "Sent", "16", "read"],
		["Dennis", "Release notes", "The notes for the release are in the usual place.", "Archive", "2", "read"]
	];
}

typedef MailFolder = {name:String, level:Int};

class MailMessage {
	public final from:String;
	public final subject:String;
	public final body:String;
	public final day:Int;
	public final folder:Signal<String>;
	public final unread:Signal<Bool>;

	public function new(from:String, subject:String, body:String, folder:String, day:Int, unread:Bool) {
		this.from = from;
		this.subject = subject;
		this.body = body;
		this.day = day;
		this.folder = signal(folder);
		this.unread = signal(unread);
	}
}

enum MailFastAction {
	Archive;
	Delete;
	MarkUnread;
}
