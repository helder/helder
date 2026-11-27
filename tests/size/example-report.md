# Size report: todo on helder.ui vs through the engine (#447, 931945c31)

Builds: release, -dce full, with symbols (macOS arm64) / name section (wasm32-wasi).
Code by Haxe package and class from nm (native) and the name section (wasm);
data by section. Scripts: scratchpad/size/{syms,report,wasmsyms}.mjs.

| | todo (helder.ui) | TodoDocument (engine) | added |
| --- | ---: | ---: | ---: |
| native file | 5.46 MB | 8.80 MB | +3.34 MB |
| native code | 3,939 KB | 6,618 KB | +2,679 KB |
| native const / data | 732 / 252 KB | 1,043 / 346 KB | +311 / +94 KB |
| wasm file | 3.96 MB | 7.24 MB | +3.28 MB |
| wasm code | 3,241 KB | 6,144 KB | +2,903 KB |

## Added code by package (native / wasm KB)

| package | native | wasm |
| --- | ---: | ---: |
| helder.css | 1,580 | 1,647 |
| helder.ui.flow | 649 | 650 |
| helder.ui.box | 401 | 373 |
| helder.dom | 134 | 104 |
| helder.css.themes (app.css as code) | 122 | 87 |
| runtime, text, canvas, other | ~120 | ~220 |

## Largest added classes (native KB)

CssTable 163, CssProperties 131, CssInitial 122 (wasm 227), app.css theme 122,
GridFlow 107, TableFlow 106, CssCanonical 92, CssColors 89, CssCalc 88,
CssShorthands 88 (wasm 143), BlockFlow 63, LineBuilder 58, CssStyles 55,
CssComputed 53, InlineContent 51, CssMatch 48, CssCounters 47, XmlParser 47,
CssResolver 43, FlexFlow 42, SelectorParser 40, BoxStyle 39, BoxTree 38.
