// fuzz (seed 200, programs 88 and 92): toUTCString's year before year 0 is
// its sign and four digits at least, not toISOString's six
for (const t of [-62198755200000, -62135596800000, -8640000000000000, -100000000000000, 0, 253402300800000, 8640000000000000])
  console.log(new Date(t).toUTCString(), new Date(t).toISOString())
