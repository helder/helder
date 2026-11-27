console.log(Math.round(0.49999999999999994), Math.round(0.5), Math.round(-0.5000000000000001));
const round = Math.round;
console.log(Object.is(round(-0.5), -0), Object.is(Math.sinh(-0), -0), Object.is(Math.tanh(-0), -0));
