# helder.dev

The program side of `helder dev`. A hosted build sends frames and logs
to the dev host. It can patch live literals, or reload the program and
restore its signals.

Use `keep(key, () => initial)` from `helder/dev` in TypeScript, or
`helder.dev.Keep.keep` in Haxe, for plain data that should survive a
reload. The initializer runs on a first build and when its source
changes. Use a stable key and store numbers, strings, booleans, null,
arrays or plain objects of those.

See [the dev command](../cli/README.md) and [the protocol](../devtools/README.md).
