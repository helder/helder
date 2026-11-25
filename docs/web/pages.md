# Pages, hydration and islands

The same components that draw your app can render a web page: to static HTML when you build, and to the DOM in the browser. Interactive parts are islands that load when needed, and a whole helder program can run inside a page as WebAssembly. These docs are built this way.

<Example id="ts-palette"/>

A page is markup written to a file when you build. An island marks where a program runs in it, and when it starts.

```tsx
import {Static, Island} from 'helder/web'

Static.write('bin/site/index.html', Static.document(<html lang='en'>
  <head><script src='loader.js' defer></script></head>
  <body>
    <h1>Palette study</h1>
    <Island.Wasm src='palette.wasm' load='visible' width={480} height={288}/>
  </body>
</html>))
```

```haxe
class Site implements Markup {
  static function main() {
    Static.write('bin/site/index.html', Static.document(<html lang='en'>
      <head><script src='loader.js' defer></script></head>
      <body>
        <h1>Palette study</h1>
        <Island.Wasm src='palette.wasm' load={Visible}
          width={480} height={288}/>
      </body>
    </html>));
  }
}
```

## What else

- **Hydration:** the browser takes over the HTML the build wrote, claiming each node instead of making it again.
- **JavaScript islands:** components compiled to small JavaScript bundles, hydrated when visible, idle or clicked.
- **WebAssembly islands:** a UI or a GPU canvas in a page, stopped when scrolled away to give its memory back.
- **Off the page's thread:** a program runs in a Web Worker on its canvas, so the page's own scripts never hold its frames back.
- **JavaScript calling WebAssembly:** typed exports between a page's scripts and your module.
- **A whole app on the web:** `helder build --target web` makes a page that fills the window with your `<Surface>`.

<Reference to="web"/>
