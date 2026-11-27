// RegExp's methods on a RegExp of RegExp.prototype's built-ins, its own
// properties lastIndex alone: matches read as captures, no match objects;
// and the same methods where something changed and they read it all.
const text = 'one two three two one';
let seen: any[] = [];
console.log(text.replace(/o/g, '0'), text.replace(/t(w|h)/g, '[$1|$&|$`]'), text.replace(/(?<w>t\w+)/, '<$<w>>'));
console.log(text.replace(/(\w)(\w+)/g, (m, a, b, at, s) => (seen.push(at), b + a)), seen);
seen = [];
const named = /(?<first>\w)(?<rest>\w*)/g;
console.log(text.replace(named, (...args: any[]) => (seen.push(JSON.stringify(args[args.length - 1])), args[2])), seen.slice(0, 2));
console.log('aaa'.replace(/a*?/g, '-'), 'abc'.replace(/(?:)/g, '.'), '\u{1F600}x'.replace(/(?:)/gu, '|'), 'xx'.replace(/$/, '!'));
console.log(text.match(/t\w+/g), text.match(/t(\w+)/), text.match(/zz/g), text.match(/zz/), 'aaa'.match(/a*?/g));
const g = /o/g;
console.log(g.test(text), g.lastIndex, g.test(text), g.lastIndex, /o/.test('x'), /^t/m.test(text));
// (a replacer sees lastIndex as the method left it: every match found first)
const watched = /o/g;
console.log(text.replace(watched, () => String(watched.lastIndex)));
const sticky = /o/y;
sticky.lastIndex = 1;
console.log('ooxo'.replace(sticky, 'S'), sticky.lastIndex, 'ooxo'.replace(sticky, 'S'), sticky.lastIndex);
const lazy = /o/;
(lazy as any).lastIndex = {valueOf() { seen.push('valueOf'); return 0; }};
seen = [];
console.log('foo'.replace(lazy, '0'), seen);

// match objects: index, input, groups in order, written, deleted, extended
const m = /(?<a>b)(c)?/.exec('abd')!;
console.log(m, m.index, m.input, m.groups, Object.keys(m), JSON.stringify(m));
(m as any).index = 9;
delete (m as any).input;
(m as any).extra = 1;
console.log(m.index, (m as any).input, Object.keys(m), Object.getOwnPropertyNames(m));
console.log([...'a1b2'.matchAll(/[a-z](\d)/g)].map(x => [x[0], x[1], x.index, x.input]), 'a,b,,c'.split(/,/), 'a1b'.split(/(\d)/), 'abc'.split(/(?:)/, 2));
const d = /(?<x>a)/d.exec('ba')!;
console.log((d as any).indices, (d as any).indices.groups);

// changed: an own exec, a subclass's (RegExp.prototype's members are frozen: TSHX001)
const own = /o/g;
(own as any).exec = function (this: RegExp, s: string) { seen.push('own exec'); (own as any).exec = undefined; delete (own as any).exec; return RegExp.prototype.exec.call(this, s); };
seen = [];
console.log('foo'.replace(own, '0'), seen);
class Loud extends RegExp {
  exec(s: string) { seen.push('Loud.exec'); return super.exec(s); }
}
seen = [];
console.log('foo'.replace(new Loud('o', 'g'), '0'), new Loud('o').test('o'), 'foo'.match(new Loud('o', 'g')), seen);
console.log('foo'.replace(/o/g, '0'), 'foo'.match(/o/g), /o/.test('o'));

// where a match can start: after assertions, alternatives' first code units in no order, line starts
const lines = 'a WARN b\nWARNING x\n\rWARN WARN end';
console.log(lines.match(/\bWARN\b/g), lines.match(/^WARN/gm), lines.match(/(?=W)WA/g), lines.match(/(?<=\s)W\w+/g), lines.match(/z|x|b/g), lines.split(/\bW/), 'éaéb'.match(/é|b/g), lines.match(/$\n?W/gm));
console.log('x1y22z'.split(/\d+/), '\u{1F600}a\u{1F600}'.split(/a/u), /^b/.exec('ab'), /\Bb/.exec('ab')!.index, 'AbAB'.match(/b/gi));

// join reads elements as they are: holes, an index on the prototype, a length past them, an own property
const joined: any[] = [1, , 'b', null, undefined, 2.5];
(joined as any).own = 1;
(Array.prototype as any)[1] = 'proto';
const longer: any[] = ['x'];
longer.length = 3;
console.log(joined.join('-'), longer.join(), [1.5, -0, NaN].join(' '), Array.prototype.join.call({length: 2, 0: 'a', 1: 'b'}, '+'));
delete (Array.prototype as any)[1];
