// npm packages: compiled from their JavaScript, typed by their declarations
/// <reference path="./untyped.d.ts" />
import {twice, Counter} from "typed";
import {shout} from "typed/sub";
import greet from "mainpkg";
import {half} from "untyped";
import {area} from "outer";
import {value} from "dual";

console.log(twice(21), shout("hi"), greet("npm"), half(9));
const c = new Counter(2);
c.add(3);
console.log(c.total, area(3), value);
