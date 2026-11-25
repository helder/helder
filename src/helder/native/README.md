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
and [helder.platform](../platform/README.md) for target-specific calls.
