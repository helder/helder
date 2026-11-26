// The window: the sidebar (the database, a search, its tables with their
// counts, a dot where changes are not saved), the open table's header
// (Back, its name and count, Data, Structure and SQL), its filter and
// actions, the grid and the row panel beside it, the changes' bar
// (Discard, Save), the status bar; while there is no server, how to start
// one; a menu over everything
import { For, Match, Read, Repeat, Show, Switch, signal } from "helder/view";
import { type Color, DataGrid, Key, Node, SafeArea, Svg, TextField, Theme, WindowControls } from "helder/ui";
import {uiOf} from 'helder/ui/actions'
import * as format from "./format";
import * as icons from "./icons";
import { Table } from "./table";
import { Entry, Link, Place, Tables, primary } from "./tables";
import * as filters from "./filters";

export const SIDEBAR = 240;
export const PANEL = 320;
const c = (name: string) => Theme.c(name);

export function view(app: Tables) {
	return <view slot="body" flexGrow={1} flexDirection="row" minHeight={0}>
		<Sidebar app={app}/>
		<view tag="main" flexGrow={1} minWidth={0} flexDirection="column">
			<Header app={app}/>
			<Switch>
				<Match when={app.state() === "offline"}><Waiting app={app}/></Match>
				<Match when={app.state() === "connecting"}><view flexGrow={1} background={c("bg")}/></Match>
				<Match when={app.mode() === "data"}><Data app={app}/></Match>
				<Match when={app.mode() === "structure"}><view flexGrow={1} minHeight={0}>{app.structure}</view></Match>
				<Match when={app.mode() === "sql"}><Console app={app}/></Match>
			</Switch>
			<Status app={app}/>
		</view>
		<Show when={app.menu() !== null}><MenuLayer app={app}/></Show>
		<Show when={app.reviewing()}><Review app={app}/></Show>
		<Show when={app.asking() !== null}><Asking app={app}/></Show>
	</view>;
}

function Icon(props: { src: Svg; color: Color; size?: number }) {
	const size = props.size ?? Theme.ICON_S;
	return <image src={props.src} width={size} height={size} color={props.color} flexShrink={0}/>;
}

// ---- the sidebar

let searchField: Node | null = null;

export function focusSearch() {
	searchField?.focus(true);
}

function Sidebar(props: { app: Tables }) {
	const app = props.app;
	const shown = () => {
		const q = app.search().toLowerCase();
		return app.tables().filter(t => q === "" || t.id.toLowerCase().includes(q));
	};
	return <view tag="sidebar" slot="panel" width={SIDEBAR} flexShrink={0} borderWidth="0 1 0 0">
		<view tag="database" flexDirection="row" alignItems="center" columnGap={8} dragRegion height={Theme.HEADER} padding={`0 ${Theme.PAD}`} flexShrink={0}
			borderWidth="0 0 1 0" borderColor={c("line")}>
			<Show when={SafeArea.titlebar() !== null}><view flexDirection="row" alignItems="center" padding="0 6 0 0"><WindowControls/></view></Show>
			<Icon src={icons.database} color={c("fg3")}/>
			<text fontWeight={Theme.MEDIUM} flexShrink={1} minWidth={0} lineClamp={1} textOverflow="ellipsis">{database(app)}</text>
			<view flexGrow={1}/>
			<text fontSize={Theme.SMALL} color={c("fg3")} flexShrink={0} lineClamp={1}>{driver(app)}</text>
		</view>
		<view padding="8 8 4" flexShrink={0}>
			<view slot="field" onPress={() => focusSearch()}>
				<Icon src={icons.search} color={c("fg3")} size={12}/>
				<field tag="search" slot="field-input" fontFamily={Theme.UI} aria-label="Search tables" placeholder="Search tables" value={app.search}
					ref={(n: Node) => (searchField = n)} onInput={(e) => app.search(e.text)} onKeyDown={(e) => {
						if (e.key === Key.ENTER) {
							const first = shown()[0];
							if (first !== undefined) app.visit(first);
						}
						if (e.key === Key.ESCAPE) {
							app.search("");
							app.grid.focus(true);
						}
					}}/>
				<text slot="kbd" padding="0 8 0 0">{primary("K")}</text>
			</view>
		</view>
		<scroll tag="tables" flexGrow={1} minHeight={0} padding="4 8 8" rowGap={1} role="list" aria-label="Tables">
			<For each={() => groups(shown())}>{(group: Read<{ schema: string; tables: Table[] }>) =>
				<view rowGap={1}>
					<view slot="section-head" padding="0 8"><text fontSize={Theme.SMALL}>{group().schema === "" ? "Tables" : group().schema}</text></view>
					<For each={group().tables}>{(table: Read<Table>) => <TableItem app={app} t={table()}/>}</For>
				</view>
			}</For>
			<Show when={app.state() === "ready" && shown().length === 0}>
				<text color={c("fg3")} padding="6 8">{app.tables().length === 0 ? "No tables yet" : "No table matches"}</text>
			</Show>
		</scroll>
	</view>;
}

// (the tables by schema, a heading each when there are several)
function groups(list: Table[]): { schema: string; tables: Table[] }[] {
	const out: { schema: string; tables: Table[] }[] = [];
	for (const t of list) {
		const s = t.schema === "main" ? "" : t.schema;
		let last = out[out.length - 1];
		if (last === undefined || last.schema !== s) out.push(last = { schema: s, tables: [] });
		last.tables.push(t);
	}
	if (out.length === 1) out[0] = { schema: "", tables: out[0].tables };
	return out;
}

function TableItem(props: { app: Tables; t: Table }) {
	const app = props.app, t = props.t;
	const on = () => (app.opening() ?? app.current()) === t;
	return <button tag={"table-" + t.id} slot="nav-item" role="listitem" aria-label={t.name} data-on={on() ? "true" : "false"}
		onPress={() => {
			if (app.mode() === "sql") app.mode("data");
			app.visit(t);
		}}>
		<Icon src={t.view ? icons.view : icons.table} color={on() ? c("accent-ink") : c("fg3")}/>
		<text flexGrow={1} minWidth={0} lineClamp={1} textOverflow="ellipsis">{t.name}</text>
		<Show when={app.pending(t)}><view width={6} height={6} borderRadius={3} background={c("sand")} aria-label="Changes not saved"/></Show>
		<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} color={c("fg3")} fontVariantNumeric="tabular-nums">
			{app.tables() !== null && t.count >= 0 ? format.count(t.count) : ""}</text>
	</button>;
}

function database(app: Tables): string {
	const s = app.setup();
	if (s === null) return app.state() === "offline" ? "Not connected" : "";
	if (s.database) return s.database;
	switch (s.dialect) {
		case "sqlite": return "SQLite";
		case "postgresql": return "PostgreSQL";
		case "mysql": return "MySQL";
		case "singlestore": return "SingleStore";
		default: return s.dialect;
	}
}

// (the driver drizzle-kit uses: its package's last part)
function driver(app: Tables): string {
	const d = app.setup()?.driver ?? "";
	return d.substring(d.lastIndexOf("/") + 1);
}

// ---- the header

function Header(props: { app: Tables }) {
	const app = props.app;
	return <view tag="header" slot="panel" flexDirection="row" alignItems="center" columnGap={6} dragRegion height={Theme.HEADER} flexShrink={0}
		padding={`0 ${Theme.PAD} 0 8`} borderWidth="0 0 1 0">
		<Show when={app.canBack()}>
			<button tag="back" slot="button" aria-label="Back" onPress={() => app.back()}><Icon src={icons.back} color={c("fg2")} size={Theme.ICON}/></button>
		</Show>
		<text fontWeight={Theme.MEDIUM} fontSize={13} lineClamp={1} textOverflow="ellipsis" minWidth={0} flexShrink={1} padding="0 4">{app.current()?.id ?? ""}</text>
		<view flexGrow={1}/>
		<Show when={app.state() === "ready"}>
			<view slot="seg" role="tablist" aria-label="View">
				<Seg app={app} mode="data" label="Data" src={icons.table}/>
				<Seg app={app} mode="structure" label="Structure" src={icons.columns}/>
				<Seg app={app} mode="sql" label="SQL" src={icons.terminal}/>
			</view>
			<button tag="refresh" slot="button" aria-label="Refresh" onPress={() => (app.mode() === "sql" ? app.run() : app.refresh())}>
				<Icon src={icons.refresh} color={c("fg2")}/>
			</button>
		</Show>
	</view>;
}

function rowsText(app: Tables): string {
	const n = app.count(), t = app.current();
	if (t === null || n < 0) return "";
	const text = n === 1 ? "1 row" : `${format.count(n)} rows`;
	const narrowed = app.applied() !== "" || app.quick() !== "" || app.conditions().length > 0;
	return narrowed && t.count >= 0 ? `${text} of ${format.count(t.count)}` : text;
}

function Seg(props: { app: Tables; mode: string; label: string; src: Svg }) {
	const app = props.app, mode = props.mode;
	return <button tag={"mode-" + mode} slot="seg-item" role="tab" aria-label={props.label} aria-selected={app.mode() === mode}
		data-on={app.mode() === mode ? "true" : "false"} onPress={() => {
			if (mode === "sql") app.showSql();
			else app.mode(mode);
			if (mode === "sql") app.editor.view.focus(false);
			else if (mode === "data") app.grid.focus(false);
		}}>
		<Icon src={props.src} color={app.mode() === mode ? c("accent-ink") : c("fg3")} size={12}/>
		<text>{props.label}</text>
	</button>;
}

// ---- the rows

let filterField: TextField | null = null;
let quickField: Node | null = null;

// the filter field focused (end: the caret after its text)
export function focusFilter(end = false) {
	const f = filterField;
	if (f === null) return;
	f.focus(true);
	if (end) setTimeout(() => {
		f.select(f.text.length, f.text.length)
	}, 0);
}

function Data(props: { app: Tables }) {
	const app = props.app;
	return <view flexGrow={1} minHeight={0}>
		<view tag="toolbar" flexDirection="row" alignItems="center" columnGap={6} height={40} padding={`0 ${Theme.PAD}`} flexShrink={0} borderWidth="0 0 1 0"
			borderColor={c("line")}>
			<view slot="field" width={200} flexShrink={0} onPress={() => quickField?.focus(true)}>
				<Icon src={icons.search} color={c("fg3")} size={14}/>
				<field tag="search-rows" slot="field-input" aria-label="Search rows" placeholder="Search rows" value={app.quick} ref={(n: Node) => (quickField = n)}
					onInput={(e) => app.searchRows(e.text)} onKeyDown={(e) => {
						if (e.key === Key.ESCAPE) {
							if (app.quick.peek() !== "") app.searchRows("");
							else app.grid.focus(true);
						}
						if (e.key === Key.ENTER || e.key === Key.DOWN) app.grid.focus(true);
					}}/>
			</view>
			<view slot="field" flexGrow={1} maxWidth={640} data-error={app.filterFailed() ? "true" : "false"} onPress={() => filterField?.focus(true)}>
				<text slot="field-label" fontFamily={Theme.CODE}>WHERE</text>
				<field tag="filter" slot="field-input" aria-label="Filter" placeholder={example(app)} value={app.filter} ref={(n: TextField) => (filterField = n)}
					onInput={(e) => app.filter(e.text)} onKeyDown={(e) => {
						if (e.key === Key.ENTER) app.applyFilter();
						if (e.key === Key.ESCAPE) {
							if (app.filter.peek() !== app.applied.peek()) app.filter(app.applied.peek());
							else if (app.applied.peek() !== "") app.clearFilter();
							app.grid.focus(true);
						}
					}}/>
				<Show when={app.applied() !== "" || app.filter() !== ""}>
					<button tag="clear-filter" slot="button" aria-label="Clear filter" height={20} minWidth={20} padding={0}
						onPress={() => app.clearFilter()}><Icon src={icons.close} color={c("fg3")} size={12}/></button>
				</Show>
			</view>
			<Show when={app.filter() !== app.applied()}><text color={c("fg3")} fontSize={Theme.SMALL}>Enter to apply</text></Show>
			<button tag="add-condition" slot="button" aria-label="Add a filter on a column" onPress={(e) => app.pickColumn(-1, below(e.target))}>
				<Icon src={icons.filter} color={c("fg2")}/><text>Filter</text>
			</button>
			<view flexGrow={1}/>
			<Show when={!(app.current()?.readOnly ?? true)} fallback={<text color={c("fg3")} fontSize={Theme.SMALL}>{readOnlyText(app)}</text>}>
				<button tag="add-row" slot="button" aria-label="Add row" onPress={() => app.addRow()}>
					<Icon src={icons.plus} color={c("fg2")}/><text>Add row</text>
				</button>
				<button tag="delete-rows" slot="button" aria-label="Delete selected rows" onPress={() => app.deleteRows()}>
					<Icon src={icons.trash} color={c("fg2")}/><text>Delete</text>
				</button>
			</Show>
			<button tag="toggle-panel" slot="button" aria-label="Row panel" data-on={app.panel() ? "true" : "false"}
				onPress={() => app.panel(!app.panel.peek())}>
				<Icon src={icons.panel} color={app.panel() ? c("accent-ink") : c("fg2")}/>
			</button>
		</view>
		<Show when={app.conditions().length > 0}>
			<view tag="conditions" flexDirection="row" flexWrap alignItems="center" columnGap={6} rowGap={6} padding={`6 ${Theme.PAD}`} flexShrink={0} borderWidth="0 0 1 0"
				borderColor={c("line")}>
				<Repeat count={app.conditions().length}>{(i: number) => <Chip app={app} index={i}/>}</Repeat>
				<button tag="clear-conditions" slot="button" aria-label="Remove every filter" onPress={() => app.clearConditions()}>
					<text color={c("fg3")}>Clear</text>
				</button>
			</view>
		</Show>
		<view flexDirection="row" flexGrow={1} minHeight={0}>
			<view flexGrow={1} minWidth={0} fontFamily={Theme.CODE} fontSize={Theme.BODY}>{app.grid}</view>
			<Show when={app.panel()}><RowPanel app={app}/></Show>
		</view>
		<Show when={app.changes() > 0}>
			<view tag="changes" slot="panel" flexDirection="row" alignItems="center" columnGap={8} height={44} padding={`0 ${Theme.PAD}`} flexShrink={0}
				borderWidth="1 0 0 0" aria-live="polite">
				<view width={6} height={6} borderRadius={3} background={c("sand")}/>
				<text>{app.changes() === 1 ? "1 unsaved change" : `${app.changes()} unsaved changes`}</text>
				<text color={c("fg3")} fontSize={Theme.SMALL}>{primary("Z") + " to undo"}</text>
				<view flexGrow={1}/>
				<button tag="discard" slot="button" aria-label="Discard changes" onPress={() => app.discard()}>
					<Icon src={icons.undo} color={c("fg2")}/><text>Discard</text>
				</button>
				<button tag="save" slot="primary" aria-label="Save changes" onPress={() => app.save()}>
					<text>{app.saving() ? "Saving…" : "Save changes"}</text>
					<text color="rgba(255,255,255,0.65)" fontWeight={400}>{primary("S")}</text>
				</button>
			</view>
		</Show>
	</view>;
}

// ---- the changes' SQL before they are saved: Save (or the save key again) runs it, Escape goes back

function Review(props: { app: Tables }) {
	const app = props.app;
	const n = app.reviewCount.peek();
	return <view tag="review-layer" position="absolute" inset={0} alignItems="center" justifyContent="center" padding={24}
		background={app.dark() ? "rgba(0,0,0,0.45)" : "rgba(0,0,0,0.16)"} onPointerDown={() => app.cancelReview()}>
		<view tag="review" slot="floating" width={680} maxWidth="100%" maxHeight="80%" padding={0} boxShadow={Theme.popover()} role="dialog" aria-label="Review changes"
			onPointerDown={(e) => e.stop()} onKeyDown={(e) => {
				if (e.key === Key.ESCAPE) {
					app.cancelReview();
					e.preventDefault();
				}
			}}>
			<view flexDirection="row" alignItems="baseline" columnGap={8} padding={`14 ${Theme.PAD + 4} 10`} flexShrink={0}>
				<text fontWeight={Theme.MEDIUM}>Review changes</text>
				<text color={c("fg3")} fontSize={Theme.SMALL}>{(n === 1 ? "1 statement" : `${n} statements`) + ", run in one transaction"}</text>
			</view>
			<view height={Math.min(360, 16 + n * 20)} minHeight={56} flexShrink={1} margin={`0 ${Theme.PAD}`} borderRadius={Theme.RADIUS} borderWidth={1}
				borderColor={c("line")} overflow="hidden">{app.review}</view>
			<view flexDirection="row" alignItems="center" justifyContent="end" columnGap={8} padding={Theme.PAD} flexShrink={0}>
				<button tag="review-cancel" slot="button" aria-label="Back to editing" onPress={() => app.cancelReview()}>
					<text>Cancel</text>
				</button>
				<button tag="review-save" slot="primary" aria-label="Save changes" autoFocus onPress={() => app.confirm()}>
					<text>Save changes</text>
					<text color="rgba(255,255,255,0.65)" fontWeight={400}>{primary("S")}</text>
				</button>
			</view>
		</view>
	</view>;
}

// (where a menu opens: under the button pressed, the target's nearest focusable ancestor)
function below(target: Node): Place {
	let n: Node = target;
	while (!n.focusable && n.parent !== null) n = n.parent;
	return { x: n.absX, y: n.absY + n.height + 4, from: n };
}

// a condition: its column and its operator (each a menu), its value, a way to remove it
function Chip(props: { app: Tables; index: number }) {
	const app = props.app, i = props.index;
	const cond = () => app.conditions()[i];
	const column = () => app.current()?.columns[cond()?.col ?? -1];
	// (a value picked from its column's: an enum's, a boolean's, compared as a whole)
	const picked = () => {
		const col = column(), op = cond()?.op;
		return col !== undefined && filters.choices(col) !== null && (op === "=" || op === "<>");
	};
	const wrong = () => {
		const t = app.current(), x = cond();
		return t !== null && x !== undefined && !filters.valid(t, x);
	};
	return <view tag={"condition-" + i} flexDirection="row" alignItems="center" height={26} borderRadius={Theme.RADIUS} borderWidth={1} borderColor={c("line")}
		background={c("bg")} overflow="hidden">
		<button slot="button" aria-label="Column" height={24} borderRadius={0} onPress={(e) => app.pickColumn(i, below(e.target))}>
			<text fontWeight={Theme.MEDIUM}>{column()?.name ?? ""}</text>
		</button>
		<button slot="button" aria-label="Operator" height={24} borderRadius={0} onPress={(e) => app.pickOp(i, below(e.target))}>
			<text color={c("fg2")}>{filters.label(cond()?.op ?? "=")}</text>
		</button>
		<Show when={filters.valued(cond()?.op ?? "=")}>
			<Show when={picked()} fallback={
				<field tag={"condition-value-" + i} aria-label="Value" placeholder={column() === undefined ? "value" : filters.hint(column()!)} width={140} height={24}
					padding="0 6" fontFamily={Theme.CODE} background={c("canvas")} value={cond()?.value ?? ""} autoFocus={(cond()?.value ?? "") === ""}
					color={wrong() ? c("red") : c("fg")} onInput={(e) => app.setCondition(i, { value: e.text }, 300)} onKeyDown={(e) => {
						if (e.key === Key.ENTER) app.grid.focus(true);
						if (e.key === Key.ESCAPE) app.grid.focus(true);
					}}/>
			}>
				<button tag={"condition-value-" + i} slot="button" aria-label="Value" autoFocus={(cond()?.value ?? "") === ""} height={24} borderRadius={0}
					minWidth={60} onPress={(e) => app.pickValue(i, below(e.target))}>
					<text fontFamily={Theme.CODE} color={(cond()?.value ?? "") === "" ? c("fg3") : c("fg")}>{(cond()?.value ?? "") === "" ? "choose" : cond()!.value}</text>
				</button>
			</Show>
		</Show>
		<button slot="button" aria-label="Remove this filter" width={24} height={24} padding={0} borderRadius={0} onPress={() => app.removeCondition(i)}>
			<Icon src={icons.close} color={c("fg3")} size={12}/>
		</button>
	</view>;
}

// ---- a question before changes are lost: Save first (when it can), Discard, Cancel (Escape)

function Asking(props: { app: Tables }) {
	const app = props.app, ask = app.asking.peek()!;
	return <view tag="ask-layer" position="absolute" inset={0} alignItems="center" justifyContent="center" padding={24}
		background={app.dark() ? "rgba(0,0,0,0.45)" : "rgba(0,0,0,0.16)"} onPointerDown={() => app.answer("cancel")}>
		<view tag="ask" slot="floating" width={400} maxWidth="100%" padding={0} boxShadow={Theme.popover()} role="alertdialog" aria-label={ask.title}
			onPointerDown={(e) => e.stop()} onKeyDown={(e) => {
				if (e.key === Key.ESCAPE) {
					app.answer("cancel");
					e.preventDefault();
				}
			}}>
			<view rowGap={6} padding={`16 ${Theme.PAD + 4} 4`}>
				<text fontWeight={Theme.MEDIUM}>{ask.title}</text>
				<text color={c("fg2")}>{ask.text}</text>
			</view>
			<view flexDirection="row" alignItems="center" columnGap={8} padding={Theme.PAD}>
				<button tag="ask-discard" slot="button" aria-label={ask.discard} onPress={() => app.answer("discard")}>
					<text color={c("red")}>{ask.discard}</text>
				</button>
				<view flexGrow={1}/>
				<button tag="ask-cancel" slot="button" aria-label="Cancel" autoFocus={ask.save === undefined} onPress={() => app.answer("cancel")}>
					<text>Cancel</text>
				</button>
				<Show when={ask.save !== undefined}>
					<button tag="ask-save" slot="primary" aria-label="Save first" autoFocus onPress={() => app.answer("save")}>
						<text>Save…</text>
					</button>
				</Show>
			</view>
		</view>
	</view>;
}

function example(app: Tables): string {
	const t = app.current();
	if (t === null || t.columns.length === 0) return "";
	const col = t.columns.find(c => !c.primary && !c.numeric) ?? t.columns[0];
	return `${app.quote(col.name)} = '…'`;
}

function readOnlyText(app: Tables): string {
	const t = app.current();
	return t === null ? "" : t.view ? "A view: read only" : "No primary key: read only";
}

// ---- the row panel: the cursor's row, a field a column, its relations

function RowPanel(props: { app: Tables }) {
	const app = props.app, t = app.current();
	if (t === null) return null;
	return <view tag="row-panel" slot="panel" width={PANEL} flexShrink={0} borderWidth="0 0 0 1">
		<view flexDirection="row" alignItems="center" columnGap={6} height={36} padding={`0 6 0 ${Theme.PAD}`} flexShrink={0}>
			<text fontWeight={Theme.MEDIUM} flexGrow={1}>{app.panelRow() < 0 ? "No row" : `Row ${format.count(app.panelRow() + 1)}`}</text>
			<text color={c("fg3")} fontSize={Theme.SMALL}>{t.readOnly ? "read only" : ""}</text>
			<button tag="close-panel" slot="button" aria-label="Close the row panel" onPress={() => app.panel(false)}>
				<Icon src={icons.close} color={c("fg3")} size={12}/>
			</button>
		</view>
		<scroll flexGrow={1} minHeight={0} scrollbarWidth="thin" scrollbarColor={c("edge")}>
			<view slot="section" rowGap={4}>
				<view slot="section-head"><text>Fields</text></view>
				<For each={t.columns.map((_, k) => k)}>{(k: Read<number>) => <FieldRow app={app} t={t} k={k()}/>}</For>
			</view>
			<Show when={app.links().length > 0}>
				<view slot="section" rowGap={1}>
					<view slot="section-head"><text>Relations</text></view>
					<For each={() => app.links()}>{(l: Read<Link>) =>
						<button slot="nav-item" role="link" aria-label={l().label} onPress={() => l().run()}>
							<Icon src={icons.link} color={c("fg3")} size={12}/>
							<text color={c("fg")} flexShrink={0}>{l().label}</text>
							<text color={c("fg3")} fontSize={Theme.SMALL} minWidth={0} lineClamp={1} textOverflow="ellipsis">{l().detail}</text>
						</button>
					}</For>
				</view>
			</Show>
		</scroll>
	</view>;
}

// (a field's label inside it, as the studio's inspector's: as wide as the others, cut when longer)
const LABEL = 76;

// a column's field: its name inside, its value (the code's font); JSON and
// long text in a taller one, its name at its top; a dot when changed
function FieldRow(props: { app: Tables; t: Table; k: number }) {
	const app = props.app, t = props.t, k = props.k, col = t.columns[k];
	// (several lines: JSON, and text that is long or has lines of its own)
	const long = () => {
		if (col.mode === "json" || col.type.toLowerCase().includes("json")) return true;
		const v = app.fieldText(k);
		return v !== null && (v.length > 40 || v.includes("\n"));
	};
	let typed: string | null = null;
	const keep = () => {
		if (typed !== null) app.setField(k, typed);
		typed = null;
	};
	const placeholder = () => {
		const f = app.fieldFlags(k);
		return (f & DataGrid.DEFAULT) !== 0 ? "DEFAULT" : (f & DataGrid.NULL) !== 0 ? "NULL" : "";
	};
	const label = () =>
		<view flexDirection="row" alignItems="center" columnGap={4} width={LABEL} flexShrink={0}>
			<text slot="field-label" minWidth={0} flexShrink={1} lineClamp={1} textOverflow="ellipsis">{col.name}</text>
			<Show when={(app.fieldFlags(k) & DataGrid.EDITED) !== 0}><view width={5} height={5} borderRadius={3} background={c("sand")} flexShrink={0}/></Show>
		</view>;
	return <Show when={long()} fallback={
		<view slot="field">
			{label()}
			<field slot="field-input" aria-label={col.name} value={app.fieldText(k) ?? ""} placeholder={placeholder()} readOnly={t.readOnly}
				onInput={(e) => (typed = e.text)} onBlur={() => keep()} onKeyDown={(e) => {
					if (e.key === Key.ENTER) keep();
				}}/>
		</view>
	}>
		<view slot="field" variant="tall">
			<view padding="2 0 0" flexShrink={0}>{label()}</view>
			<textarea slot="field-input" variant="tall" spellCheck={false} maxHeight={240} aria-label={col.name} value={app.fieldText(k) ?? ""}
				placeholder={placeholder()} readOnly={t.readOnly} onInput={(e) => (typed = e.text)} onBlur={() => keep()} onKeyDown={(e) => {
					if (e.key === Key.ENTER && (e.mods.includes("meta") || e.mods.includes("control"))) keep();
				}}/>
		</view>
	</Show>;
}

// ---- the console

function Console(props: { app: Tables }) {
	const app = props.app;
	return <view flexGrow={1} minHeight={0}>
		<view height="38%" minHeight={120} flexShrink={0} padding="8 0 0" background={c("bg")}>{app.editor}</view>
		<view flexDirection="row" alignItems="center" columnGap={10} height={40} padding={`0 ${Theme.PAD}`} flexShrink={0} borderWidth="1 0 1 0" borderColor={c("line")}
			background={c("bg")}>
			<button tag="run" slot="primary" aria-label="Run query" onPress={() => app.run()}>
				<Icon src={icons.play} color={c("accent-fg")} size={12}/><text>Run</text>
				<text color="rgba(255,255,255,0.65)" fontWeight={400}>{primary("↵")}</text>
			</button>
			<text color={app.resultFailed() ? c("red") : c("fg3")} lineClamp={2} textOverflow="ellipsis" minWidth={0} flexShrink={1} selectable>{app.resultNote}</text>
		</view>
		<view flexGrow={1} minHeight={0} fontFamily={Theme.CODE} fontSize={Theme.BODY}>{app.results}</view>
	</view>;
}

// ---- no server yet

function Waiting(props: { app: Tables }) {
	return <view flexGrow={1} alignItems="center" justifyContent="center" padding={24} background={c("bg")}>
		<view width={420} maxWidth="100%" rowGap={12}>
			<text fontSize={15} fontWeight={Theme.MEDIUM}>Waiting for drizzle-kit studio</text>
			<text color={c("fg2")} lineHeight={1.5}>Run Drizzle's studio server in your project. This window connects to it as soon as it starts.</text>
			<view slot="field" height={32} padding="0 12" cursor="default">
				<text fontFamily={Theme.CODE} color={c("fg")} selectable>npx drizzle-kit studio</text>
			</view>
			<text color={c("fg3")} fontSize={Theme.SMALL}>{`Looking at ${props.app.url}`}</text>
		</view>
	</view>;
}

// ---- the status bar

function Status(props: { app: Tables }) {
	const app = props.app;
	return <view tag="status" slot="panel" flexDirection="row" alignItems="center" columnGap={12} height={26} padding={`0 ${Theme.PAD}`} flexShrink={0}
		borderWidth="1 0 0 0" fontSize={Theme.SMALL} color={c("fg3")}>
		<Show when={app.note() === ""} fallback={
			<text tag="note" color={app.failed() ? c("red") : c("fg2")} lineClamp={1} textOverflow="ellipsis" minWidth={0} flexShrink={1} selectable aria-live="polite">
				{app.note}</text>
		}>
			<text lineClamp={1} minWidth={0}>{app.state() === "ready" ? "Connected" : app.state() === "offline" ? "Not connected" : "Connecting"}</text>
		</Show>
		<view flexGrow={1}/>
		<Show when={app.mode() === "data"}>
			<text lineClamp={1} fontVariantNumeric="tabular-nums">{rowsText(app)}</text>
			<text lineClamp={1} fontVariantNumeric="tabular-nums">{app.cell}</text>
			<text lineClamp={1} fontVariantNumeric="tabular-nums">{app.took() > 0 ? `${Math.round(app.took() * 1000)} ms` : ""}</text>
		</Show>
	</view>;
}

// ---- a menu: its items, Up and Down between them, Enter, Escape; kept inside the window

function MenuLayer(props: { app: Tables }) {
	const app = props.app, m = app.menu()!;
	// (the items' nodes, in order, and their items)
	const nodes: Node[] = [], entries: Entry[] = [];
	const first = m.items.find(i => i.on) ?? m.items.find(i => !i.line && !i.disabled);
	// (its place: where it was asked for, moved inside the window once it is laid out)
	const at = signal({ x: m.x, y: m.y });
	const close = () => {
		app.menu(null);
		if (m.from !== undefined && uiOf(m.from) !== null) m.from.focus(false)
		else app.grid.focus(false)
	};
	const step = (d: number) => {
		const on = nodes.findIndex(n => n.focused);
		let i = on < 0 ? (d > 0 ? -1 : nodes.length) : on;
		do i += d;
		while (i >= 0 && i < nodes.length && entries[i].disabled);
		if (i >= 0 && i < nodes.length) nodes[i].focus(true);
	};
	return <view tag="menu-layer" position="absolute" inset={0} onPointerDown={() => close()}>
		<view tag="menu" slot="floating" position="absolute" left={at().x} top={at().y} minWidth={Math.max(200, m.width ?? 0)} maxHeight={420}
			boxShadow={Theme.popover()} role="menu" onPointerDown={(e) => e.stop()} onResize={(e) => at(inside(e.target, at.peek()))} onKeyDown={(e) => {
				if (e.key === Key.ESCAPE) close();
				if (e.key === Key.DOWN) {
					step(1);
					e.preventDefault();
				}
				if (e.key === Key.UP) {
					step(-1);
					e.preventDefault();
				}
			}}>
			<scroll minHeight={0} flexShrink={1}>
				<For each={m.items}>{(item: Read<Entry>) => {
					const i = item();
					return i.line ? <view height={1} margin="4 4" background={c("line")}/> :
						<button slot="menu-item" role="menuitem" aria-label={i.label} data-disabled={i.disabled ? "true" : "false"} aria-selected={i.on === true}
							autoFocus={i === first} ref={(n: Node) => {
								nodes.push(n);
								entries.push(i);
							}} onPress={() => {
								if (i.disabled) return;
								close();
								i.run();
							}}>
							<view width={Theme.ICON_S} flexShrink={0}>{i.on ? <Icon src={icons.check} color={c("accent-ink")}/> : i.icon ? <Icon src={i.icon} color={c("fg3")}/> : null}</view>
							<text flexGrow={1} lineClamp={1} color={i.muted ? c("fg3") : c("fg")}>{i.label}</text>
							<text color={c("fg3")} fontSize={Theme.SMALL}>{i.detail ?? ""}</text>
						</button>;
				}}</For>
			</scroll>
		</view>
	</view>;
}

// (a menu's place inside the window: moved left or up where it would go past an edge)
function inside(n: Node, at: { x: number; y: number }): { x: number; y: number } {
	const layer = n.parent;
	if (layer === null) return at;
	const w = layer.width, h = layer.height;
	const x = at.x + n.width > w - 8 ? Math.max(8, w - n.width - 8) : at.x;
	const y = at.y + n.height > h - 8 ? Math.max(8, h - n.height - 8) : at.y;
	return x === at.x && y === at.y ? at : { x, y };
}
