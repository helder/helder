package helder.async;

// helder.async for TypeScript programs (helder.typescript): a program's
// promises and timers already run on helder.async's loop (its async
// functions as the graph's async computations, typescript's README); these are
// helder.async's own tasks, each a promise to the program (a Task<T> is a
// Promise<T>). Its HTTP client and server are a whole package: their
// coroutines are the program's async functions (helder.typescript.api.Coroutines).
@:typescript("helder/async")
@:typescript.packages(helder.async.http)
@:typescript.classes(helder.async.Fetch)
@:typescript.functions(delay = helder.async.Tasks.delay)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
