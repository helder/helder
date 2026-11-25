# helder.headless

Run an app without a display. Drive its UI with a timed script of clicks,
keys and text, take PNG snapshots and print the node tree. The app uses
the same layout and input handling as a window.

```sh
npx helder run --headless --size 480x360 --snap counter.png --at 1 src/main.tsx
```

Pass `--script` to replay input or `--tree` to read the rendered nodes.
See [Headless runs](../cli/README.md#headless-runs) for the script format
and flags.

The run itself is helder.os's headless platform (`helder.os.headless`:
its windows, the script, the virtual clock's steps, the snapshots); this
package keeps what it draws over the frames for a screencast (`--keys`,
`--pointer`: `Overlay`, on helder.canvas and helder.text).
