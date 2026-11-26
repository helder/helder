// Numbers as text where the runtime writes integers by their digits: around
// 2^31, 2^32 and 2^53, negative zero, past 1e21, fractions; through
// concatenation, templates, JSON, join, String and property keys.
const nums = [0, -0, 1, -1, 7, 10, 2147483647, 2147483648, -2147483648, -2147483649, 4294967295, 4294967296, 1000000000, 1000000001, -1000000000, 999999999999, 123456789012, 9007199254740991, -9007199254740991, 9007199254740992, -9007199254740992, 9007199254740994, 1e20, 1e21, -1e21, 0.5, -1.5e-7, 1e-7, 1.5, 2 ** 52 + 0.5, 1e300, NaN, Infinity, -Infinity]
console.log(nums.map(n => '' + n).join(' '))
console.log(nums.map(n => `${n}`).join(' '))
console.log(JSON.stringify(nums), nums.join(','), nums.map(String).join(' '))
const o: Record<string, number> = {}
for (const n of nums) o[n] = 1
console.log(Object.keys(o).join(' '))
const a: number[] = []
a[4294967294] = 1
console.log(Object.keys(a), a.length, [1, 2, 3][1], ({1: 'x'} as Record<string, string>)['1'], [10, 20]['1' as any])
