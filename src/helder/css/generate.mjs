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
  if (!d) throw Error('no such type: ' + name)
  d.syntax = o.syntax
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
typedef CssProperty = {
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
\tpublic static final properties:Array<CssProperty> = [
`
hx += chosen.map(p => `\t\t{name: ${s(p.name)}, module: ${s(p.module)}, href: ${s(p.href)}, syntax: ${s(p.syntax)}, initial: ${s(p.initial)}, inherited: ${p.inherited}, appliesTo: ${s(p.appliesTo)}, percentages: ${s(p.percentages)}, computed: ${s(p.computed)}, animation: ${s(p.animation)}, longhands: ${list(p.longhands)}, alias: ${s(p.alias)}}`).join(',\n')
hx += '\n\t];\n\n\tpublic static final types:Array<CssType> = [\n'
const typeList = [...named.values()].sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : a.scope.length - b.scope.length)
hx += typeList.map(t => `\t\t{name: ${s(t.name)}, scope: ${list(t.scope)}, syntax: ${s(t.syntax)}, href: ${s(t.href)}}`).join(',\n')
hx += '\n\t];\n\n\tpublic static final descriptors:Array<CssDescriptor> = [\n'
hx += descriptors.map(d => `\t\t{rule: ${s(d.rule)}, name: ${s(d.name)}, syntax: ${s(d.syntax)}, initial: ${s(d.initial)}}`).join(',\n')
hx += '\n\t];\n}\n'
fs.writeFileSync(out + '/CssData.hx', hx)

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
