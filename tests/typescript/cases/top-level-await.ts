// skip: top-level await: a module's body is no async function yet (TSHX001:
// await outside an async function); found writing the fuzzer's plain tests
const x = await Promise.resolve(3)
console.log(x, await new Promise<string>(r => setTimeout(() => r('later'), 0)))
export {}
