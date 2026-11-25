# Navigation

A `Router` holds your app's screens by path, as a stack; a `Stack` shows it. Screens slide in the way the platform's own do, the system's back pops them (Android's back, Escape, the browser's), and in a browser each screen is a URL, so a reload or a shared link opens it.

<Image src="navigation.webp" alt="A fruit list sliding left and dimming as the Cherry screen slides in from the right" caption="examples/navigation, captured headless halfway through a push."/>

Routes match in order; `:id` takes one segment and arrives typed. Each screen is made once, when it is pushed, and kept with its state while covered.

```tsx
import {Router, Stack} from 'helder/ui'

const nav = new Router()
  .route('/', () => <Home/>)
  .route('/product/:id', p => <Product id={p.id}/>)
  .fallback(path => <NotFound path={path}/>)

const stack = <Stack router={nav}/>

nav.go('/product/3')   // push
nav.back()             // pop
```

```haxe
final nav = new Routes();
nav.route('/', _ -> <Home/>)
  .route('/product/:id', p -> <Product id={p.id}/>)   // p: {id:String}
  .fallback(path -> <NotFound path={path}/>);

<Stack router={nav}/>

nav.go('/product/3');   // push
nav.back();             // pop
```

## What else

- **Moves:** `go`, `back`, `replace` the top, `reset` to a new stack, and `open` a link, which builds the root and the screen it names.
- **Reads:** the top's path, query and depth, as signals.
- **Transitions:** iOS's slide with its edge swipe back, Android's, a fade elsewhere, or none; reduced motion turns slides into fades.
- **Deep links:** `App.onOpen = urls -> nav.open(urls[0])` opens the screen a link names ([Device services](services.md)).
- **Accessibility:** the new screen's first control takes the focus and its title is announced.

<Reference to="ui"/>
