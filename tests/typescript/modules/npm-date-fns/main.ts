// A real package: date-fns 4.1.0 (MIT, its LICENSE.md beside it), the
// modules these functions reach as published (a package.json of their
// exports only); differenceInMonths' `difference - +isLastMonthNotFull`
import {format} from "date-fns/format";
import {addDays} from "date-fns/addDays";
import {differenceInDays} from "date-fns/differenceInDays";
import {differenceInMonths} from "date-fns/differenceInMonths";
import {parseISO} from "date-fns/parseISO";
import {formatDistance} from "date-fns/formatDistance";
import {isWeekend} from "date-fns/isWeekend";

const d = new Date(2024, 0, 15, 12, 30, 0);
console.log(format(d, "yyyy-MM-dd HH:mm"), format(addDays(d, 3), "EEEE do MMMM yyyy"));
console.log(differenceInDays(addDays(d, 10), d), differenceInMonths(new Date(2024, 4, 31), new Date(2024, 1, 29)));
console.log(format(parseISO("2024-02-29T08:05:00"), "PPpp"), isWeekend(parseISO("2024-03-02")));
for (const days of [0, 1, 6, 40, 400]) console.log(formatDistance(addDays(d, days), d), "/", formatDistance(d, addDays(d, days), {addSuffix: true}));
console.log(format(d, "QQQ yyyy, 'week' w, h a"));
