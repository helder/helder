// Writes CssData.hx from @webref/css (pinned below) and scope.json; run from
// the repository's root: node src/helder/css/generate.mjs
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import {spawnSync} from 'node:child_process'

const version = '8.7.10'
const url = `https://registry.npmjs.org/@webref/css/-/css-${version}.tgz`
const dir = path.resolve('bin/webref/' + version)
const out = 'src/helder/css'
const at = ['@page', '@font-face', '@media']

const tgz = path.join(dir, 'css.tgz')
fs.mkdirSync(dir, {recursive: true})
if (!fs.existsSync(tgz)) sh('curl', ['-fsSL', '--max-time', '120', url, '-o', tgz])
if (!fs.existsSync(path.join(dir, 'package/css.json'))) sh('tar', ['xzf', tgz, '-C', dir, 'package/css.json'])
const sha256 = crypto.createHash('sha256').update(fs.readFileSync(tgz)).digest('hex')
const manifestFile = out + '/manifest.json'
if (fs.existsSync(manifestFile)) {
  const old = JSON.parse(fs.readFileSync(manifestFile, 'utf8'))
  if (old.version === version && old.sha256 !== sha256) throw Error('@webref/css hash changed: ' + version)
}

const css = JSON.parse(fs.readFileSync(path.join(dir, 'package/css.json'), 'utf8'))
const scope = JSON.parse(fs.readFileSync(out + '/scope.json', 'utf8'))
const spec = href => href.split('#')[0].replace(/\/$/, '').split('/').pop()
const byName = list => {
  const map = new Map()
  // (a name defined again for one rule or function, `for`, keeps the general one)
  for (const x of list) if (!map.has(x.name) || map.get(x.name).for) map.set(x.name, x)
  return map
}
const properties = byName(css.properties), types = byName(css.types), functions = byName(css.functions)

const module = new Map()
for (const [m, names] of Object.entries(scope.modules))
  for (const name of names) {
    if (!properties.has(name)) throw Error('no such property: ' + name)
    if (module.has(name)) throw Error('listed twice: ' + name)
    module.set(name, m)
  }
const reason = new Map()
for (const [why, names] of Object.entries(scope.out))
  for (const name of names) {
    if (!properties.has(name)) throw Error('no such property: ' + name)
    if (module.has(name)) throw Error('in and out: ' + name)
    reason.set(name, why)
  }
const unexplained = [...properties.values()]
  .filter(p => !module.has(p.name) && !reason.has(p.name) && !scope.outSpecs[spec(p.href)])
  .map(p => `${p.name} (${spec(p.href)})`)
if (unexplained.length) throw Error('in or out? ' + unexplained.join(', '))

const syntax = p => scope.overrides[p.name]?.syntax ?? p.syntax ?? null
const chosen = [...module.keys()].sort().map(name => {
  const p = properties.get(name)
  for (const l of p.longhands ?? []) if (!module.has(l)) throw Error(`${name}'s longhand ${l} is out of scope`)
  if (p.legacyAliasOf && !module.has(p.legacyAliasOf)) throw Error(`${name} aliases ${p.legacyAliasOf}, out of scope`)
  return {
    name, module: module.get(name), href: scope.overrides[name]?.href ?? p.href,
    syntax: syntax(p), initial: p.initial ?? null,
    inherited: /^yes\b/.test(p.inherited ?? '') ? true : /^no\b/.test(p.inherited ?? '') ? false : null,
    appliesTo: p.appliesTo ?? null, percentages: p.percentages ?? null,
    computed: p.computedValue ?? null, animation: p.animationType ?? null,
    longhands: p.longhands ?? [], alias: p.legacyAliasOf ?? null
  }
})
// (a legacy name has its property's definition; a shorthand inherits as all its longhands do)
const byChosen = new Map(chosen.map(p => [p.name, p]))
for (const p of chosen) if (p.alias)
  for (const k of ['initial', 'inherited', 'appliesTo', 'percentages', 'computed', 'animation'])
    if (p[k] == null) p[k] = byChosen.get(p.alias)[k]
for (const p of chosen) if (p.inherited == null && p.longhands.length) {
  const flags = new Set(p.longhands.map(l => byChosen.get(l).inherited))
  if (flags.size === 1) p.inherited = [...flags][0]
}
const descriptors = css.atrules.filter(a => at.includes(a.name))
  .flatMap(a => a.descriptors.map(d => ({rule: a.name, name: d.name, syntax: d.syntax ?? null, initial: d.initial ?? null})))

// The named types the grammars reference, all the way down. A name defined
// again for some properties or types (webref's `for`: clip's rect(), grid's
// repeat()) is taken in their context, as CssProperties.type does; `<'p'>`
// of a property out of scope is kept as the type "'p'".
const defs = new Map()
for (const x of [...css.types, ...css.functions]) defs.set(x.name, [...defs.get(x.name) ?? [], x])
for (const [name, o] of Object.entries(scope.types)) {
  const d = defs.get(name)?.find(d => !d.for)
  // (a type webref references but doesn't define: scope.json's)
  if (!d) defs.set(name, [{name, syntax: o.syntax, href: o.href ?? null}])
  else d.syntax = o.syntax
}
const scoped = new Set([...defs.values()].flat().flatMap(d => d.for ?? []))
const pick = (name, context) => {
  const all = defs.get(name)
  return all && (all.find(d => d.for?.some(f => context.includes(f))) ?? all.find(d => !d.for) ?? all[0])
}
const named = new Map(), missing = new Set(), seen = new Set()
const queue = [...chosen.map(p => [p.syntax, [p.name]]), ...descriptors.map(d => [d.syntax, [d.rule, d.name]])]
while (queue.length) {
  const [text, context] = queue.pop()
  if (!text) continue
  for (const [, prop, type] of text.matchAll(/<'([^'\s>]+)'>|<([A-Za-z][\w+-]*(?:\(\))?)/g)) {
    if (prop && module.has(prop)) continue
    const name = prop ? `'${prop}'` : type
    const def = prop ? properties.get(prop) : pick(type, context)
    if (!def) {
      missing.add(name)
      continue
    }
    const inner = [...context, prop ?? (type.endsWith('()') ? type : `<${type}>`)].filter(c => scoped.has(c))
    const key = name + ' ' + [...new Set(inner)].sort().join(' ')
    if (seen.has(key)) continue
    seen.add(key)
    named.set(def, {name, scope: prop ? [] : def.for ?? [], syntax: def.syntax ?? null, href: def.href})
    queue.push([def.syntax, [context[0], ...inner]])
  }
}
if (missing.size) throw Error('undefined types: ' + [...missing].join(' '))
const primitives = [...named.values()].filter(t => t.syntax == null).map(t => t.name)
const unlisted = primitives.filter(n => !scope.primitives[n])
if (unlisted.length) throw Error('types without a grammar (scope.json primitives?): ' + unlisted.join(' '))

const s = x => x == null ? 'null' : JSON.stringify(x)
const list = xs => '[' + xs.map(s).join(', ') + ']'
let hx = `package helder.css;

// Generated by generate.mjs (beside it) from @webref/css ${version} (MIT; the
// grammars and prose are the CSS specs', W3C's): scope.json's properties,
// the types and functions their grammars reference, and the descriptors of
// ${at.join(', ')}. Inputs and hash: manifest.json.
typedef CssPropertyData = {
\tname:String,
\tmodule:String,
\thref:String,
\tsyntax:String,
\tinitial:Null<String>,
\tinherited:Null<Bool>,
\tappliesTo:Null<String>,
\tpercentages:Null<String>,
\tcomputed:Null<String>,
\tanimation:Null<String>,
\tlonghands:Array<String>,
\talias:Null<String>
}

typedef CssType = {name:String, scope:Array<String>, syntax:Null<String>, href:Null<String>}
typedef CssDescriptor = {rule:String, name:String, syntax:Null<String>, initial:Null<String>}

class CssData {
\tpublic static final properties:Array<CssPropertyData> = [
`
hx += chosen.map(p => `\t\t{name: ${s(p.name)}, module: ${s(p.module)}, href: ${s(p.href)}, syntax: ${s(p.syntax)}, initial: ${s(p.initial)}, inherited: ${p.inherited}, appliesTo: ${s(p.appliesTo)}, percentages: ${s(p.percentages)}, computed: ${s(p.computed)}, animation: ${s(p.animation)}, longhands: ${list(p.longhands)}, alias: ${s(p.alias)}}`).join(',\n')
hx += '\n\t];\n\n\tpublic static final types:Array<CssType> = [\n'
const typeList = [...named.values()].sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : a.scope.length - b.scope.length)
hx += typeList.map(t => `\t\t{name: ${s(t.name)}, scope: ${list(t.scope)}, syntax: ${s(t.syntax)}, href: ${s(t.href)}}`).join(',\n')
hx += '\n\t];\n\n\tpublic static final descriptors:Array<CssDescriptor> = [\n'
hx += descriptors.map(d => `\t\t{rule: ${s(d.rule)}, name: ${s(d.name)}, syntax: ${s(d.syntax)}, initial: ${s(d.initial)}}`).join(',\n')
hx += '\n\t];\n}\n'
fs.writeFileSync(out + '/CssData.hx', hx)

// ---- the run time's table: what parsing and computing need, no prose
let table = `package helder.css;

// Generated by generate.mjs (beside it) from @webref/css ${version}: what
// the run time needs of CssData (the grammars, initial values, inheritance,
// longhands, legacy names), without its prose and links.
typedef CssDefinition = {name:String, syntax:String, initial:Null<String>, inherited:Null<Bool>, longhands:Array<String>, alias:Null<String>}
typedef CssTypeDefinition = {name:String, scope:Array<String>, syntax:Null<String>}

class CssTable {
\tpublic static final properties:Array<CssDefinition> = [
`
// (a shorthand's initial value is its longhands': prose, left out; box-shadow is stored whole)
table += chosen.map(p => `\t\t{name: ${s(p.name)}, syntax: ${s(p.syntax)}, initial: ${s(p.longhands.length && p.name !== 'box-shadow' || p.name === 'all' ? null : p.initial)}, inherited: ${p.inherited}, longhands: ${list(p.longhands)}, alias: ${s(p.alias)}}`).join(',\n')
table += '\n\t];\n\n\tpublic static final types:Array<CssTypeDefinition> = [\n'
table += typeList.map(t => `\t\t{name: ${s(t.name)}, scope: ${list(t.scope)}, syntax: ${s(t.syntax)}}`).join(',\n')
table += '\n\t];\n}\n'
fs.writeFileSync(out + '/CssTable.hx', table)

// ---- computed styles' storage (styles.json): ids, groups, typed values
const styles = JSON.parse(fs.readFileSync(out + '/styles.json', 'utf8'))
const typeSyntax = new Map()
for (const t of typeList) if (t.syntax != null && (!typeSyntax.has(t.name) || !t.scope.length)) typeSyntax.set(t.name, t.syntax)
const isLogical = p => p.module === 'css-logical-1' && !p.longhands.length
const stored = chosen.filter(p => !p.alias && (!p.longhands.length || p.name === 'box-shadow') && !isLogical(p) && !styles.unstored[p.name])
const logical = chosen.filter(isLogical)
const groupOf = new Map()
const groupNames = Object.keys(styles.groups)
for (const [g, def] of Object.entries(styles.groups))
  for (const name of def.properties) {
    const p = byChosen.get(name)
    if (!p) throw Error(`styles.json: ${name} isn't in scope`)
    if (groupOf.has(name)) throw Error(`styles.json: ${name} is in two groups`)
    if ((p.inherited === true) !== def.inherited) throw Error(`styles.json: ${name} ${p.inherited ? 'inherits' : "doesn't inherit"}, its group ${g} doesn't`)
    groupOf.set(name, g)
  }
const ungrouped = stored.filter(p => !groupOf.has(p.name)).map(p => p.name)
if (ungrouped.length) throw Error('styles.json: in no group: ' + ungrouped.join(' '))
for (const name of groupOf.keys()) if (!stored.some(p => p.name === name)) throw Error(`styles.json: ${name} isn't stored`)

// (a grammar's top-level alternatives, each a keyword, a length, a number,
// a colour or something else, types looked through)
function alternatives(text) {
  const out = []
  let depth = 0, cur = ''
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '[' || c === '(') depth++
    else if (c === ']' || c === ')') depth--
    if (depth === 0 && c === '|' && text[i + 1] !== '|' && text[i - 1] !== '|') {
      out.push(cur.trim())
      cur = ''
    } else cur += c
  }
  out.push(cur.trim())
  return out
}
function atoms(text, seen = new Set()) {
  const out = []
  for (let a of alternatives(text)) {
    const inner = /^\[(.*)\]$/.exec(a)
    if (inner && balanced(inner[1])) {
      out.push(...atoms(inner[1].trim(), seen))
      continue
    }
    let m
    if (/^[a-zA-Z][\w-]*$/.test(a)) out.push('kw:' + a.toLowerCase())
    // (a function: its values kept aside, CssGroup's others)
    else if (/^<[\w-]+\(\)>$/.test(a) || oneFunction(a)) out.push('X')
    else if ((m = /^<'([\w-]+)'>$/.exec(a)) && byChosen.has(m[1]) && !seen.has(m[1])) out.push(...atoms(byChosen.get(m[1]).syntax, new Set([...seen, m[1]])))
    else if ((m = /^<([\w-]+)(?:\s*\[[^\]]*\])?>$/.exec(a))) {
      const n = m[1]
      if (['length', 'length-percentage', 'percentage'].includes(n)) out.push('L')
      else if (['number', 'integer'].includes(n)) out.push(n === 'integer' ? 'I' : 'N')
      else if (n === 'color') out.push('C')
      else if (typeSyntax.has(n) && !seen.has(n)) out.push(...atoms(typeSyntax.get(n), new Set([...seen, n])))
      else out.push('F')
    } else out.push('F')
  }
  return out
}
function oneFunction(t) {
  const m = /^[\w-]+\(/.exec(t)
  if (!m || !t.endsWith(')')) return false
  let d = 0
  for (let i = m[0].length - 1; i < t.length; i++) {
    if (t[i] === '(') d++
    else if (t[i] === ')' && --d === 0) return i === t.length - 1
  }
  return false
}
function balanced(t) {
  let d = 0
  for (const c of t) {
    if (c === '[') d++
    else if (c === ']' && --d < 0) return false
  }
  return d === 0
}
function kindOf(p) {
  const all = atoms(p.syntax)
  const keywords = [...new Set(all.filter(a => a.startsWith('kw:')).map(a => a.slice(3)))]
  const has = new Set(all.filter(a => !a.startsWith('kw:') && a !== 'X'))
  let kind = styles.kinds[p.name]
  if (!kind)
    kind = has.size === 0 ? 'keyword'
      : (has.has('N') || has.has('I')) && !has.has('L') && !has.has('C') && !has.has('F') ? 'number'
      : has.has('L') && [...has].every(a => a === 'L' || a === 'N' || a === 'I') ? 'length'
      : has.size === 1 && has.has('C') ? 'color'
      : 'terms'
  return {kind, keywords, integer: has.has('I') && !has.has('N')}
}

const pascal = n => n.split('-').map(w => w[0].toUpperCase() + w.slice(1)).join('')
const camel = n => { const x = pascal(n); const c = x[0].toLowerCase() + x.slice(1); return c === 'continue' ? 'continues' : c }
const ids = [...stored, ...logical].sort((a, b) => a.name < b.name ? -1 : 1)
const idOf = new Map(ids.map((p, i) => [p.name, i]))
const info = new Map(stored.map(p => [p.name, kindOf(p)]))
const impactOf = name => styles.impact[name] ?? styles.groups[groupOf.get(name)].impact
// (logical to physical, horizontal-tb: block-start top, block-end bottom, inline-start left (rtl: right))
const physical = (name, rtl) => name
  .replace(/^(min-|max-)?inline-size$/, (_, m) => (m ?? '') + 'width').replace(/^(min-|max-)?block-size$/, (_, m) => (m ?? '') + 'height')
  .replace(/^inset-/, '').replace(/^border-(start|end)-(start|end)-radius$/, (_, b, i) => `border-${b === 'start' ? 'top' : 'bottom'}-${(i === 'start') !== rtl ? 'left' : 'right'}-radius`)
  .replace('block-start', 'top').replace('block-end', 'bottom')
  .replace('inline-start', rtl ? 'right' : 'left').replace('inline-end', rtl ? 'left' : 'right')
for (const p of logical) for (const rtl of [false, true]) if (!info.has(physical(p.name, rtl))) throw Error(`${p.name}: no physical ${physical(p.name, rtl)}`)

let prop = `package helder.css;

// Generated by generate.mjs (beside it) from scope.json and styles.json:
// every longhand the cascade stores, and the logical ones it maps to them,
// by id.
enum abstract CssProperty(Int) to Int {
${ids.map((p, i) => `\tvar ${pascal(p.name)} = ${i};`).join('\n')}
}
`
fs.writeFileSync(out + '/CssProperty.hx', prop)

const kindCode = {keyword: 0, number: 1, length: 2, color: 3, display: 4, terms: 5}
const impactCode = {layout: 0, text: 1, paint: 2, composite: 3, none: 4}
let meta = `package helder.css;

import helder.css.CssProperty;
import helder.css.CssTerm;

// Generated by generate.mjs (beside it) from scope.json and styles.json:
// what a change to a property redoes.
enum abstract CssImpact(Int) {
\tvar Layout;
\t// inherited text that lays text out again
\tvar Text;
\tvar Paint;
\t// opacity and transforms
\tvar Composite;
\tvar None;
}

// Generated by generate.mjs (beside it): each property's name, group (-1: a
// logical one), kind (0 keyword, 1 number, 2 length, 3 colour, 4 display,
// 5 terms), keywords, impact, and a logical one's physical property
// (horizontal-tb, ltr and rtl).
class CssProperties {
\tpublic static inline var COUNT = ${ids.length};
\tpublic static final groups:Array<String> = ${list(groupNames)};
\tstatic final names:Array<String> = ${list(ids.map(p => p.name))};
\tstatic final group:Array<Int> = [${ids.map(p => groupOf.has(p.name) ? groupNames.indexOf(groupOf.get(p.name)) : -1).join(', ')}];
\tstatic final kind:Array<Int> = [${ids.map(p => info.has(p.name) ? kindCode[info.get(p.name).kind] : -1).join(', ')}];
\tstatic final impacts:Array<Int> = [${ids.map(p => impactCode[info.has(p.name) ? impactOf(p.name) : impactOf(physical(p.name, false))]).join(', ')}];
\tstatic final inherited:Array<Bool> = [${ids.map(p => p.inherited === true).join(', ')}];
\tstatic final ltr:Array<Int> = [${ids.map(p => info.has(p.name) ? idOf.get(p.name) : idOf.get(physical(p.name, false))).join(', ')}];
\tstatic final rtl:Array<Int> = [${ids.map(p => info.has(p.name) ? idOf.get(p.name) : idOf.get(physical(p.name, true))).join(', ')}];
\tstatic final words:Array<Array<String>> = [${ids.map(p => info.has(p.name) && ['keyword', 'number', 'color', 'length'].includes(info.get(p.name).kind) ? list(info.get(p.name).keywords) : '[]').join(', ')}];
\t// (each group's properties)
\tpublic static final members:Array<Array<Int>> = [${groupNames.map(g => '[' + styles.groups[g].properties.map(n => idOf.get(n)).join(', ') + ']').join(', ')}];
\tstatic var byName:Null<Map<String, CssProperty>>;

\tpublic static function of(name:String):Null<CssProperty> {
\t\tif (byName == null) byName = [for (k in 0...COUNT) names[k] => cast k];
\t\treturn byName.get(name);
\t}

\tpublic static inline function name(p:CssProperty):String
\t\treturn names[p];

\t// (the group's index in CssStyle, -1 for a logical property)
\tpublic static inline function groupOf(p:CssProperty):Int
\t\treturn group[p];

\tpublic static inline function kindOf(p:CssProperty):Int
\t\treturn kind[p];

\tpublic static inline function impact(p:CssProperty):CssImpact
\t\treturn cast impacts[p];

\tpublic static inline function inherits(p:CssProperty):Bool
\t\treturn inherited[p];

\tpublic static inline function logical(p:CssProperty):Bool
\t\treturn group[p] < 0;

\t// A logical property's physical one for the direction (horizontal-tb); a physical one itself.
\tpublic static inline function physical(p:CssProperty, rtl:Bool):CssProperty
\t\treturn cast (rtl ? rtl_ : ltr_)[p];

\tpublic static inline function keywords(p:CssProperty):Array<String>
\t\treturn words[p];

\t// (a keyword's terms, one array a keyword, shared: never to be changed)
\tpublic static function keywordTerms(p:CssProperty, index:Int):Array<CssTerm> {
\t\tif (terms == null) terms = [for (k in 0...COUNT) [for (w in words[k]) [Keyword(w)]]];
\t\treturn terms[p][index];
\t}

\tstatic var terms:Null<Array<Array<Array<CssTerm>>>>;
}
`
meta = meta.replace('(rtl ? rtl_ : ltr_)[p]', '(rtl ? CssProperties.rtl : CssProperties.ltr)[p]')
fs.writeFileSync(out + '/CssProperties.hx', meta)

// (keyword properties' enums, the keywords' indices: shared where styles.json says)
const enumOf = new Map(), enums = new Map()
for (const [name, i] of info) if (i.kind === 'keyword') {
  const e = styles.enums?.[name] ?? 'Css' + pascal(name)
  const words = JSON.stringify(i.keywords)
  if (enums.has(e) && enums.get(e).words !== words) throw Error(`styles.json: ${e}'s properties have different keywords`)
  enums.set(e, {words, keywords: i.keywords, properties: [...(enums.get(e)?.properties ?? []), name]})
  enumOf.set(name, e)
}
const valueName = k => pascal(k.replace(/^-+/, '').toLowerCase())
let keywordsHx = `package helder.css;

// Generated by generate.mjs (beside it) from styles.json: the keyword
// properties' computed values (CssGroups' fields), each keyword its index
// in CssProperties.keywords; Other: a value the keywords don't cover (the
// group's others has it).
`
for (const [e, d] of [...enums].sort()) keywordsHx += `
// ${d.properties.join(', ')}
enum abstract ${e}(Int) to Int {
${d.keywords.map((k, i) => `\tvar ${valueName(k)} = ${i};`).join('\n')}
\tvar Other = -2;
}
`
fs.writeFileSync(out + '/CssKeywords.hx', keywordsHx)

// (a group's class: a field per property, typed by its kind)
const fieldType = {keyword: 'Int', number: 'Float', length: 'CssLength', color: 'CssRgba', display: 'CssDisplay', terms: 'Array<CssTerm>'}
const typeOf = p => p.kind === 'keyword' ? enumOf.get(p.name) : fieldType[p.kind]
let groups = `package helder.css;

import helder.css.CssKeywords;
import helder.css.CssProperty;
import helder.css.CssTerm;

// Generated by generate.mjs (beside it) from styles.json: computed styles'
// groups, a field per property, typed by its kind: a keyword as its index
// in CssProperties.keywords (-2: in others), a number unboxed (NaN: a
// keyword, its index in the ...Keyword field), a length, a colour, a
// display decoded, anything else as its terms. Immutable once interned.
`
for (const [g, def] of Object.entries(styles.groups)) {
  const cls = `Css${pascal(g)}Group`
  const ps = def.properties.map(n => ({name: n, id: idOf.get(n), field: camel(n), ...info.get(n)}))
  groups += `
// ${def.inherited ? 'Inherited' : 'Not inherited'}: ${def.properties.join(', ')}.
class ${cls} extends CssGroup {
${ps.map(p => `\tpublic var ${p.field}(default, null):${typeOf(p)};` + (p.kind === 'number' && p.keywords.length ? `\n\tpublic var ${p.field}Keyword(default, null):Int = -1;` : '')).join('\n')}

\t@:allow(helder.css)
\tfunction new() {}

\toverride function copy():CssGroup {
\t\tvar g = new ${cls}();
${ps.map(p => `\t\tg.${p.field} = ${p.field};` + (p.kind === 'number' && p.keywords.length ? ` g.${p.field}Keyword = ${p.field}Keyword;` : '')).join('\n')}
\t\tg.others = others;
\t\treturn g;
\t}

\toverride function set(p:CssProperty, t:Array<CssTerm>, intern:CssIntern) {
\t\tforget(p);
\t\tswitch (p : Int) {
${ps.map(p => `\t\t\tcase ${p.id}: ${setter(p)}`).join('\n')}
\t\t\tcase _:
\t\t}
\t}

\toverride public function terms(p:CssProperty):Array<CssTerm>
\t\treturn switch (p : Int) {
${ps.map(p => `\t\t\tcase ${p.id}: ${getter(p)}`).join('\n')}
\t\t\tcase _: throw 'not in ${g}: ' + CssProperties.name(p);
\t\t}

\toverride function lengthOf(p:CssProperty):Null<CssLength>
\t\treturn switch (p : Int) {
${ps.filter(p => p.kind === 'length').map(p => `\t\t\tcase ${p.id}: ${p.field};`).join('\n')}
\t\t\tcase _: null;
\t\t}

\toverride function rgbaOf(p:CssProperty):Null<CssRgba>
\t\treturn switch (p : Int) {
${ps.filter(p => p.kind === 'color').map(p => `\t\t\tcase ${p.id}: ${p.field};`).join('\n')}
\t\t\tcase _: null;
\t\t}

\toverride function keywordOf(p:CssProperty):Int
\t\treturn switch (p : Int) {
${ps.filter(p => p.kind === 'keyword').map(p => `\t\t\tcase ${p.id}: ${p.field};`).join('\n')}
${ps.filter(p => p.kind === 'number' && p.keywords.length).map(p => `\t\t\tcase ${p.id}: ${p.field}Keyword;`).join('\n')}
\t\t\tcase _: -1;
\t\t}

\toverride function numberOf(p:CssProperty):Float
\t\treturn switch (p : Int) {
${ps.filter(p => p.kind === 'number').map(p => `\t\t\tcase ${p.id}: ${p.field};`).join('\n')}
\t\t\tcase _: Math.NaN;
\t\t}

\toverride function same(o:CssGroup):Bool {
\t\tvar g:${cls} = cast o;
\t\treturn ${ps.map(p => compare(p)).join('\n\t\t\t&& ')} && sameOthers(g);
\t}

\toverride function hash():Int {
\t\tvar h = 17;
${ps.map(p => `\t\th = h * 31 + ${hashOf(p)};`).join('\n')}
\t\treturn h;
\t}
}
`
}
function setter(p) {
  switch (p.kind) {
    case 'keyword': return `${p.field} = cast keyword(p, t);`
    case 'number': return p.keywords.length ? `{${p.field} = number(p, t, ${p.integer}); ${p.field}Keyword = numberKeyword(p, t);}` : `${p.field} = number(p, t, ${p.integer});`
    case 'length': return `${p.field} = intern.length(t) ?? other(p, t, CssLength.OTHER);`
    case 'color': return `${p.field} = intern.rgba(t) ?? other(p, t, CssRgba.OTHER);`
    case 'display': return `${p.field} = intern.display(t);`
    case 'terms': return `${p.field} = intern.terms(t);`
  }
}
function getter(p) {
  switch (p.kind) {
    case 'keyword': return `(${p.field} : Int) >= 0 ? CssProperties.keywordTerms(p, ${p.field}) : others.get(p);`
    case 'number': return p.keywords.length
      ? `${p.field}Keyword >= 0 ? CssProperties.keywordTerms(p, ${p.field}Keyword) : ${p.field}Keyword == -2 ? others.get(p) : [Number(${p.field}, ${p.integer})];`
      : `others != null && others.exists(p) ? others.get(p) : [Number(${p.field}, ${p.integer})];`
    case 'length': case 'color': return `${p.field}.id < 0 ? others.get(p) : ${p.field}.terms;`
    case 'display': return `${p.field}.terms;`
    case 'terms': return `${p.field};`
  }
}
function compare(p) {
  if (p.kind === 'number') return `(${p.field} == g.${p.field} || ${p.field} != ${p.field} && g.${p.field} != g.${p.field})` + (p.keywords.length ? ` && ${p.field}Keyword == g.${p.field}Keyword` : '')
  return `${p.field} == g.${p.field}`
}
function hashOf(p) {
  switch (p.kind) {
    case 'keyword': return `(${p.field} : Int)`
    case 'number': return `CssGroup.floatHash(${p.field})` + (p.keywords.length ? ` + ${p.field}Keyword` : '')
    case 'length': case 'color': case 'display': return `${p.field}.id`
    case 'terms': return `intern.id(${p.field})`
  }
}
groups = groups.replaceAll('\toverride function hash():Int {', '\toverride function hash(intern:CssIntern):Int {')
// (every group: an instance by index, for CssStyle)
groups += `
class CssGroups {
\tpublic static inline var COUNT = ${groupNames.length};

\tpublic static function make(group:Int):CssGroup
\t\treturn switch group {
${groupNames.map((g, i) => `\t\t\tcase ${i}: new Css${pascal(g)}Group();`).join('\n')}
\t\t\tcase _: throw 'no group ' + group;
\t\t}

\tstatic final INHERITED = ${list(groupNames.map(g => styles.groups[g].inherited)).replaceAll('"', '')};

\tpublic static inline function inherited(group:Int):Bool
\t\treturn INHERITED[group];
}
`
groups += `
// A computed style's groups, typed (CssStyle's): a few pointers, the
// inherited ones its parent's unless something in them is set.
class CssStyleGroups {
${groupNames.map(g => `\tpublic var ${camel(g)}(default, null):Css${pascal(g)}Group;`).join('\n')}

\tfunction group(i:Int):CssGroup
\t\treturn switch i {
${groupNames.map((g, i) => `\t\t\tcase ${i}: ${camel(g)};`).join('\n')}
\t\t\tcase _: throw 'no group ' + i;
\t\t}

\tfunction setGroup(i:Int, g:CssGroup)
\t\tswitch i {
${groupNames.map((g, i) => `\t\t\tcase ${i}: ${camel(g)} = cast g;`).join('\n')}
\t\t\tcase _:
\t\t}
}
`
fs.writeFileSync(out + '/CssGroups.hx', groups)
const kinds = {}
for (const [n, i] of info) kinds[i.kind] = (kinds[i.kind] ?? 0) + 1
console.log('ids', ids.length, 'stored', stored.length, 'logical', logical.length, 'groups', groupNames.length, kinds)

const outBySpec = {}
for (const p of properties.values()) {
  const why = reason.get(p.name) ?? (!module.has(p.name) ? scope.outSpecs[spec(p.href)] : null)
  if (why) outBySpec[why] = (outBySpec[why] ?? 0) + 1
}
const counts = {
  properties: chosen.length, types: typeList.length,
  primitives: typeList.filter(t => t.syntax == null).length,
  descriptors: descriptors.length, out: [...properties.keys()].length - chosen.length
}
fs.writeFileSync(manifestFile, JSON.stringify({version, url, sha256, license: 'MIT', counts, out: outBySpec}, null, 2) + '\n')
console.log(counts)

function sh(cmd, args) {
  const r = spawnSync(cmd, args, {encoding: 'utf8'})
  if (r.status !== 0) throw Error(`${cmd}: ${r.stderr}`)
}
