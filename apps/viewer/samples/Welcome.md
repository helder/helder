# Welcome to Viewer

Viewer is a fast image viewer and file browser built on
[helder](https://helder.build) alone. This page is a **Markdown** file, shown
the way the viewer shows every `.md` file: a column of text, its links
followed, its pictures from the same folder.

![A planet, from examples/planet](Planet.jpg)

## What is in this folder

- **Photos**: [Murmuration](Murmuration.jpg), [Starlings](Starlings.jpg) and a
  [wide panorama](Dusk%20panorama.jpg)
- **A PDF** of three pages: [About Viewer](About%20Viewer.pdf)
- **A video and a sound**: Starlings.mp4, Chimes.m4a
- More pictures in the [More](More) folder

## Keys

| Key | In a document |
| :-- | :-- |
| Space, Page Down | a screen down |
| Up, Down | a line |
| Home, End | the top, the end |
| Left, Right | the folder's previous and next file |
| Ctrl+U (Cmd+U on a Mac) | the source |

## A bit of code

```ts
import { Markdown, MarkdownView } from "helder/markdown";

const view = new MarkdownView({ doc: Markdown.parse(text) });
```

> Everything here was made for the viewer's samples, under the MIT license.

- [x] Open a folder of your own with **Open folder**
- [ ] Drop files on the page

Back to [the top](#welcome-to-viewer).
