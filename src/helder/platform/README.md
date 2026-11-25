# helder.platform

Read the build's OS, exact target and architecture from TypeScript.
The compiler folds `platform.os`, `platform.target` and `platform.arm`
and keeps only the selected branch of a condition on them.

```ts
import {platform} from 'helder/platform'

if (platform.os === 'windows') useWin32()
else if (platform.os === 'macos') useCocoa()
```

Read the fields directly. They are compile-time constants. See
[index.ts](index.ts) for the values and [helder.native](../native/README.md)
for calling a platform's libraries.
