// fuzz (seed 300, program 380): a number's text is the shortest that reads
// back, a power of two's too (2^-97, a float32's bits read back: 16 digits,
// not hxmc's 17), whose interval below it is half the one above
const dv = new DataView(new ArrayBuffer(8))
dv.setInt16(3, 15)
console.log([dv.getUint8(3), dv.getInt16(0), dv.getUint32(0, true), dv.getFloat32(4)])
const texts: string[] = []
for (let e = -1074; e <= 1023; e++) texts.push(String(2 ** e))
for (let i = 0; i < texts.length; i += 64) console.log(texts.slice(i, i + 64).join(' '))
console.log(`${-(2 ** -97)}`, JSON.stringify([2 ** 70, 2 ** -1000]), (2 ** -97).toString())
