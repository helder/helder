import helder.canvas.Bitmap;
import helder.canvas.Canvas;
import helder.canvas.Paint;
import helder.canvas.Path;

// examples/document's page when no file is given: text, a table, flex and
// grid sections, floats, images and links, with :hover, :active and
// :focus-visible rules; its images drawn here (image), by name.
class SamplePage {
	public static function image(url:String):Null<Bitmap> {
		var name = url.substr(url.lastIndexOf("/") + 1);
		var hue = switch name {
			case "harbour.png": [0xFF2E6F9E, 0xFF9FD3F2];
			case "field.png": [0xFF4E8A3A, 0xFFE9D77A];
			case "dusk.png": [0xFF6B3E8C, 0xFFF29E7A];
			case _: return null;
		}
		var w = 240, h = 160, c = new Canvas(w, h);
		var p = new Path();
		p.rect(0, 0, w, h);
		c.fill(p, Paint.solid(hue[1]));
		for (k in 0...5) {
			var hill = new Path();
			hill.moveTo(0, h);
			hill.lineTo(0, h * (0.5 + k * 0.1));
			hill.quadTo(w * (0.3 + k * 0.1), h * (0.25 + k * 0.12), w, h * (0.55 + k * 0.08));
			hill.lineTo(w, h);
			hill.close();
			var a = 0x30 + k * 0x28;
			c.fill(hill, Paint.solid((a << 24) | (hue[0] & 0xFFFFFF)));
		}
		return c.snapshot();
	}

	public static final HTML = '<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>The engine, live</title>
<style>
  :root { --ink: #1f2328; --muted: #59636e; --line: #d1d9e0; --accent: #0969da; --wash: #f6f8fa }
  body { margin: 0; font: 16px/1.5 system-ui, sans-serif; color: var(--ink); background: #fff }
  header { background: linear-gradient(135deg, #0b3d91, #0969da); color: #fff; padding: 32px 40px }
  header h1 { margin: 0 0 4px; font-size: 32px; line-height: 1.2 }
  header p { margin: 0; opacity: 0.85 }
  nav { display: flex; gap: 8px; padding: 10px 40px; border-bottom: 1px solid var(--line); background: var(--wash); position: sticky; top: 0 }
  nav a { padding: 4px 10px; border-radius: 6px; color: var(--ink); text-decoration: none }
  nav a:hover { background: #e7ecf0 }
  nav a:active { background: #d0d7de }
  main { max-width: 860px; margin: 0 auto; padding: 8px 40px 48px }
  h2 { margin: 36px 0 12px; font-size: 24px; border-bottom: 1px solid var(--line); padding-bottom: 6px }
  a { color: var(--accent) }
  a:hover { color: #0550ae; text-decoration-thickness: 2px }
  a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 3px }
  .lead { font-size: 18px; color: var(--muted) }
  .figure { float: right; width: 240px; margin: 4px 0 12px 20px; border: 1px solid var(--line); border-radius: 8px; padding: 6px; background: #fff }
  .figure img { display: block; width: 240px; height: 160px; border-radius: 4px }
  .figure span { display: block; font-size: 13px; color: var(--muted); padding: 4px 2px 0 }
  .left { float: left; margin: 4px 20px 12px 0 }
  table { border-collapse: collapse; width: 100%; font-size: 14px; margin: 12px 0 }
  th, td { border: 1px solid var(--line); padding: 6px 10px; text-align: left }
  th { background: var(--wash) }
  tbody tr:hover { background: #fff8c5 }
  td.n { text-align: right; font-variant-numeric: tabular-nums }
  .cards { display: flex; flex-wrap: wrap; gap: 16px; margin: 16px 0 }
  .card { flex: 1 1 220px; border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; background: #fff; box-shadow: 0 1px 2px rgb(0 0 0 / 0.06) }
  .card:hover { background: var(--wash); border-color: #8c959f }
  .card h3 { margin: 0 0 6px; font-size: 17px }
  .card p { margin: 0; color: var(--muted); font-size: 14px }
  .grid { display: grid; grid-template-columns: repeat(3, 1fr); grid-auto-rows: 90px; gap: 10px; margin: 16px 0 }
  .grid div { border-radius: 8px; padding: 10px; color: #fff; font-weight: 600 }
  .grid div:hover { opacity: 0.85 }
  .grid .wide { grid-column: span 2 }
  .grid .tall { grid-row: span 2 }
  ol li, ul li { margin: 4px 0 }
  code { font: 14px ui-monospace, monospace; background: var(--wash); padding: 1px 5px; border-radius: 4px }
  blockquote { margin: 16px 0; padding: 4px 16px; border-left: 4px solid var(--line); color: var(--muted) }
  footer { border-top: 1px solid var(--line); padding: 20px 40px; color: var(--muted); font-size: 14px; background: var(--wash) }
</style>
</head>
<body>
<header>
  <h1>The engine, live</h1>
  <p>An HTML page styled, laid out and painted by helder&rsquo;s CSS engine, inside a helder.ui window.</p>
</header>
<nav><a href="#text">Text</a><a href="#table">Table</a><a href="#flex">Flex</a><a href="#grid">Grid</a><a href="#floats">Floats</a><a href="https://html.spec.whatwg.org/">The HTML Standard</a></nav>
<main>
<h2 id="text">Text</h2>
<p class="lead">One tree, helder.dom, styled by helder.css, laid out by helder.ui.flow into fragments, and painted by the same painter that prints PDFs.</p>
<p>Hover a link to see <a href="#text">:hover</a> restyle only the element under the pointer: a colour change repaints, nothing is laid out again.
Press and drag to select text; Tab moves the focus between the links, with a <code>:focus-visible</code> ring. Scrolling moves the page on the
compositor: no style, no layout and no paint unless the page reaches past what was recorded.</p>
<blockquote>The whole document is laid out once; a resize lays it out again from the layout cache, keyed on each box&rsquo;s constraints.</blockquote>
<ul><li>Block and inline formatting contexts, line breaking, bidi</li><li>Tables, floats, positioning, flex and grid</li><li>Generated content, counters and lists</li></ul>

<h2 id="table">A table</h2>
<table>
  <thead><tr><th>Stage</th><th>What it does</th><th>Cost</th></tr></thead>
  <tbody>
    <tr><td>Cascade</td><td>Matches selectors through a rule index and a Bloom filter, shares styles between siblings</td><td class="n">per element</td></tr>
    <tr><td>Box tree</td><td>Boxes by display: anonymous blocks, table parts, generated content</td><td class="n">per box</td></tr>
    <tr><td>Layout</td><td>Formatting contexts into flat fragments, cached by constraints</td><td class="n">per change</td></tr>
    <tr><td>Paint</td><td>Appendix E&rsquo;s order, culled to the view, recorded for the GPU</td><td class="n">per frame</td></tr>
  </tbody>
</table>

<h2 id="flex">Flex</h2>
<div class="cards">
  <div class="card"><h3>Hover</h3><p>A background and a border colour: repainted, not laid out.</p></div>
  <div class="card"><h3>Select</h3><p>Dragging selects text across blocks, with the lines&rsquo; carets.</p></div>
  <div class="card"><h3>Links</h3><p>A click on a link calls the host&rsquo;s handler.</p></div>
  <div class="card"><h3>Resize</h3><p>The cards wrap again at a new width.</p></div>
</div>

<h2 id="grid">Grid</h2>
<div class="grid">
  <div class="wide" style="background:#0969da">wide</div><div class="tall" style="background:#8250df">tall</div>
  <div style="background:#1a7f37">one</div><div style="background:#bf3989">two</div><div style="background:#cf222e">three</div>
</div>

<h2 id="floats">Floats</h2>
<div class="figure"><img src="harbour.png" alt="A harbour"><span>A floated figure: the text flows around it.</span></div>
<p>Floats sit at the top of the line they are met in, and the lines around them are laid out again until they stay. This paragraph runs
beside the figure, then below it. Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore
et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p>
<p><img class="left" src="field.png" width="120" height="80" alt="A field">Duis aute irure dolor in reprehenderit in voluptate velit esse cillum
dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est
laborum. Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium.</p>
<p style="clear: both">An inline image <img src="dusk.png" width="48" height="32" alt="Dusk"> sits on the line&rsquo;s baseline, as text does.</p>
<ol><li>Back to the <a href="#text">top</a></li><li>Or read <a href="https://html.spec.whatwg.org/#the-a-element">the a element</a></li></ol>
</main>
<footer>Drawn by helder.ui.box through helder.ui&rsquo;s renderer.</footer>
</body>
</html>';
}
