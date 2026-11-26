// skip: case mapping is hxmc's String's, one code unit to one: Unicode's
// SpecialCasing (ß, ligatures, İ), Final_Sigma, titlecase digraphs and the
// astral planes' letters are not mapped yet
// fuzz (seed 100, programs 21 and 28)
for (const s of ['straße', 'ﬀ', 'ǅ', 'İstanbul', 'ΑΣ', 'ΌΣΟΣ.', 'ǰ', '𐐀', '𐐨'])
  console.log(JSON.stringify([s, s.toUpperCase(), s.toLowerCase()]))
