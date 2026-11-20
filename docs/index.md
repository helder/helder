# Introduction

helder builds apps and games in TypeScript or Haxe from one codebase. It compiles your program to native code for macOS, Windows, Linux, iOS and Android, and to WebAssembly for the web, and draws everything itself on the GPU: the same pixels on every screen.

<Image src="notes.webp" alt="A notes app with folders, a list of notes and an editor, drawn by helder" caption="A notes app made with helder, captured headless by helder run --headless."/>

## The platforms

<Platforms/>

## How it's built

- **One renderer.** `helder.gfx` speaks Metal, Direct3D 11, OpenGL, WebGPU and WebGL2. The UI, 2D and 3D all draw through it.
- **One UI.** Signals hold state and markup reads it. Layout is CSS flexbox, text is shaped by helder itself, and accessibility reaches the platform's screen readers.
- **One toolchain.** The `helder` command builds, runs, reloads, tests and publishes. It makes APKs and iPhone apps without the Android SDK or Xcode.
- **No runtime to ship.** Your program is compiled ahead of time with [hxmc](https://github.com/benmerckx/hxmc). A small app is a few megabytes natively and a few hundred kilobytes as WebAssembly.

helder is in early preview: its APIs and commands change between nightlies.

## The guide

<Sections/>

Each page is a short tour. The complete reference for every package lives in its README on GitHub, linked at the end of each page.
