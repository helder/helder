# helder.dom's XML parser's fixtures and their trees, made by expat (Python's
# xml.parsers.expat, namespaces on, as an independent reference): a sample of
# WPT's css/CSS2 .xht files and its .svg files, at the WPT revision
# import-html5lib.mjs pins, and the cases below, written as
# tests/dom/fixtures/xml/<name> and <name>.tree (html5lib's format with
# namespaces as {uri}, XmlCheck.hx's Dump.xml); a case expat refuses is
# expected to fail (.tree: "error"). The XHTML and MathML DTDs' public
# identifiers the HTML Standard lists stand for its named character
# references (an external subset of them, src/helder/dom/Entities.hx's).
#
#   python3 tests/dom/import-xml.py <wpt checkout with css/CSS2>
import os, re, sys, xml.parsers.expat as expat

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, 'fixtures', 'xml')
wpt = sys.argv[1]

HTML_IDS = {'-//W3C//DTD XHTML 1.0 Transitional//EN', '-//W3C//DTD XHTML 1.1//EN', '-//W3C//DTD XHTML 1.0 Strict//EN', '-//W3C//DTD XHTML 1.0 Frameset//EN',
	'-//W3C//DTD XHTML Basic 1.0//EN', '-//W3C//DTD XHTML 1.1 plus MathML 2.0//EN', '-//W3C//DTD XHTML 1.1 plus MathML 2.0 plus SVG 1.1//EN',
	'-//W3C//DTD MathML 2.0//EN', '-//WAPFORUM//DTD XHTML Mobile 1.0//EN', '-//WAPFORUM//DTD XHTML Mobile 1.1//EN', '-//WAPFORUM//DTD XHTML Mobile 1.2//EN'}
XHTML = 'http://www.w3.org/1999/xhtml'

data = re.search(r'static final DATA = (.*?);\n', open(os.path.join(here, '../../src/helder/dom/Entities.hx')).read(), re.S).group(1)
data = ''.join(re.findall(r'"([^"]*)"', data))
DTD = ''.join(f'<!ENTITY {n[:-1]} "{"".join(f"&#x{c};" for c in cps.split("."))}">' for n, cps in (e.split(' ') for e in data.split(',')) if n.endswith(';'))


def tree(text):
	p = expat.ParserCreate(namespace_separator=' ')
	p.namespace_prefixes = True
	p.SetParamEntityParsing(expat.XML_PARAM_ENTITY_PARSING_ALWAYS)
	lines, stack, decls = [], [], []
	state = {'text': None, 'cdata': None, 'doctype': False, 'skipped': False}
	depth = lambda: len(stack)
	pad = lambda d: '| ' + '  ' * d

	def flush():
		if state['text'] is not None:
			lines.append(pad(depth() + extra()) + '"' + state['text'] + '"')
			state['text'] = None

	def extra():
		return sum(1 for t in stack if t)

	def name(n):
		parts = n.split(' ')
		if len(parts) == 1: return parts[0], None
		uri, local = parts[0], parts[1]
		prefix = parts[2] if len(parts) > 2 else None
		return (prefix + ':' + local if prefix else local), uri

	def start(n, attrs):
		flush()
		q, uri = name(n)
		d = depth() + extra()
		lines.append(pad(d) + '<' + q + (' {' + uri + '}' if uri else '') + '>')
		items = []
		for prefix, ns in decls:
			items.append(('xmlns:' + prefix if prefix else 'xmlns') + ' {http://www.w3.org/2000/xmlns/}="' + (ns or '') + '"')
		decls.clear()
		for k, v in attrs.items():
			aq, auri = name(k)
			items.append(aq + (' {' + auri + '}' if auri else '') + '="' + v + '"')
		for a in sorted(items): lines.append(pad(d) + '  ' + a)
		template = uri == XHTML and q.split(':')[-1] == 'template'
		if template: lines.append(pad(d) + '  content')
		stack.append(template)

	def end(n):
		flush()
		stack.pop()

	def chars(t):
		if state['cdata'] is not None: state['cdata'] += t
		elif depth() > 0: state['text'] = (state['text'] or '') + t

	def cdata_start():
		flush()
		state['cdata'] = ''

	def cdata_end():
		lines.append(pad(depth() + extra()) + '<![CDATA[' + state['cdata'] + ']]>')
		state['cdata'] = None

	def comment(t):
		if state['doctype']: return
		flush()
		lines.append(pad(depth() + extra()) + '<!-- ' + t + ' -->')

	def pi(target, d):
		if state['doctype']: return
		flush()
		lines.append(pad(depth() + extra()) + '<?' + target + ' ' + d + '?>')

	def doctype(n, sysid, pubid, internal):
		lines.append(f'| <!DOCTYPE {n} "{pubid or ""}" "{sysid or ""}">')
		state['doctype'] = True
		state['html'] = pubid in HTML_IDS

	def doctype_end():
		state['doctype'] = False

	def external(context, base, sysid, pubid):
		if pubid in HTML_IDS:
			e = p.ExternalEntityParserCreate(context)
			e.Parse(DTD, True)
		return 1

	def skipped(n, pe):
		if not pe: state['skipped'] = True

	p.StartElementHandler, p.EndElementHandler, p.CharacterDataHandler = start, end, chars
	p.StartCdataSectionHandler, p.EndCdataSectionHandler = cdata_start, cdata_end
	p.CommentHandler, p.ProcessingInstructionHandler = comment, pi
	p.StartDoctypeDeclHandler, p.EndDoctypeDeclHandler = doctype, doctype_end
	p.StartNamespaceDeclHandler = lambda prefix, uri: decls.append((prefix, uri))
	p.ExternalEntityRefHandler, p.SkippedEntityHandler = external, skipped
	p.Parse(text, True)
	if state['skipped']: raise ValueError('an entity expat skipped')
	return '\n'.join(lines) + '\n'


# (well-formed and not: the parser's namespaces, references, sections and errors)
CASES = {
	'namespaces.xml': '<a xmlns="urn:a" xmlns:b="urn:b"><b:c b:d="1" e="2"/><f xmlns=""><b:g/></f><h xmlns="urn:h"/></a>',
	'xml-prefix.xml': '<a xml:lang="en" xmlns:x="urn:x"><x:b xml:space="preserve"> </x:b></a>',
	'references.xml': '<a t="&lt;&amp;&#65;&#x42;">&lt;&gt;&amp;&apos;&quot;&#169;&#x1F600;</a>',
	'internal-entities.xml': '<!DOCTYPE a [<!ENTITY e "text &#38;#38; more"><!ENTITY m "<b>bold &e;</b>"><!ELEMENT a ANY><!ATTLIST a x CDATA #IMPLIED>]><a x="&e;">&e; &m; end</a>',
	'cdata.xml': '<a><![CDATA[<not> &markup;]]>after<![CDATA[]]></a>',
	'comments-pis.xml': '<?xml version="1.0" encoding="UTF-8"?>\n<!-- before --><?style href="a"?><a><!--in--><?p data here?></a><!--after-->',
	'whitespace.xml': '<a\r\n  b="x\ty\nz\r\nw">line\r\nbreaks\rhere</a>',
	'bom.xml': '﻿<a/>',
	'standalone.xml': '<?xml version="1.0" standalone="yes"?><a/>',
	'xhtml-entities.xht': '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"><html xmlns="http://www.w3.org/1999/xhtml"><body><p title="&eacute;">&nbsp;&mdash;&times;</p></body></html>',
	'template.xht': '<html xmlns="http://www.w3.org/1999/xhtml"><body><template><p>in</p>text</template></body></html>',
	'svg.svg': '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1 1"><use xlink:href="#a"/><foreignObject><div xmlns="http://www.w3.org/1999/xhtml">x</div></foreignObject></svg>',
	'error-mismatch.xml': '<a><b></a></b>',
	'error-unbound.xml': '<a><p:b/></a>',
	'error-duplicate.xml': '<a x="1" x="2"/>',
	'error-duplicate-expanded.xml': '<a xmlns:p="urn:x" xmlns:q="urn:x" p:x="1" q:x="2"/>',
	'error-comment.xml': '<a><!-- a -- b --></a>',
	'error-cdata-end.xml': '<a>x ]]> y</a>',
	'error-undefined-entity.xml': '<a>&nbsp;</a>',
	'error-recursive.xml': '<!DOCTYPE a [<!ENTITY e "&e;">]><a>&e;</a>',
	'error-lt.xml': '<a x="<"/>',
	'error-no-root.xml': '<!-- nothing -->',
	'error-after-root.xml': '<a/>text',
	'error-two-roots.xml': '<a/><b/>',
	'error-pi-target.xml': '<a><?xml version="1.0"?></a>',
	'error-character.xml': '<a>\x01</a>',
	'error-reference.xml': '<a>&#0;</a>',
	'error-unclosed.xml': '<a><b>',
	'error-xmlns-prefix.xml': '<a xmlns:xmlns="urn:x"/>',
	'error-empty-prefix.xml': '<a xmlns:p=""/>',
	'error-qname.xml': '<a:b:c xmlns:a="urn:a"/>',
}

os.makedirs(out, exist_ok=True)
for f in os.listdir(out): os.remove(os.path.join(out, f))
files = {}
for k, v in CASES.items(): files[k] = v
css2 = os.path.join(wpt, 'css', 'CSS2')
xht, svg = [], []
for root, _, names in os.walk(css2):
	for n in names:
		rel = os.path.relpath(os.path.join(root, n), css2)
		if n.endswith('.xht'): xht.append(rel)
		elif n.endswith('.svg'): svg.append(rel)
def utf8(r):
	try:
		open(os.path.join(css2, r), encoding='utf-8').read()
		return True
	except UnicodeDecodeError:
		return False
# (UTF-8 files only: parseXml reads a string, decoded before; some tests are in other encodings)
xht = sorted(r for r in xht if utf8(r))
svg = sorted(r for r in svg if utf8(r))
# (every 100th .xht, and every 40th of those with a CDATA section, SVG or MathML: about 150)
pick = set(xht[::100])
special = [r for r in xht if re.search(r'<!\[CDATA\[|<svg|<math', open(os.path.join(css2, r), encoding='utf-8').read())]
pick |= set(special[::40])
for r in sorted(pick) + svg:
	files['css2-' + r.replace('/', '-')] = open(os.path.join(css2, r), encoding='utf-8', newline='').read()

written = 0
for n, text in files.items():
	try:
		t = tree(text)
	except (expat.ExpatError, ValueError):
		t = 'error\n'
	if n.startswith('css2-') and t == 'error\n': continue
	with open(os.path.join(out, n), 'w', encoding='utf-8', newline='') as f: f.write(text)
	with open(os.path.join(out, n + '.tree'), 'w', encoding='utf-8', newline='') as f: f.write(t)
	written += 1
print(f'tests/dom/fixtures/xml: {written} documents')
