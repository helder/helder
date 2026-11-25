# helder.native

Call native libraries from TypeScript. `native.c`, `native.objc`,
`native.com` and `native.jni` declare C functions, Objective-C messages,
COM interfaces and Java methods. The compiler reads their signatures
from the types and emits the calls with your program.

```ts
import {native, i32} from 'helder/native'

const libc = native.c({fns: {getpid: (): i32 => 0}})
console.log(libc.getpid())
```

Omit `lib` for libc. The declaration's body is a placeholder. See
[index.ts](index.ts) for types, library names and calling conventions,
and [the platform](#the-platform) below for target-specific calls.

## The platform

Read the build's OS, exact target and architecture from TypeScript.
The compiler folds `platform.os`, `platform.target` and `platform.arm`
and keeps only the selected branch of a condition on them.

```ts
import {platform} from 'helder/native/platform'

if (platform.os === 'windows') useWin32()
else if (platform.os === 'macos') useCocoa()
```

Read the fields directly. They are compile-time constants. See
[platform.ts](platform.ts) for the values.
