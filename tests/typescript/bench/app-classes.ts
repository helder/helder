// App-style classes: a hierarchy with getters, overridden methods, super
// calls, a static counter, instanceof and toString in templates.
abstract class Shape {
  static made = 0
  readonly id: number
  constructor(public name: string) { this.id = Shape.made++ }
  abstract get area(): number
  get label(): string { return `${this.name}#${this.id}` }
  describe(): string { return `${this.label}: ${this.area.toFixed(1)}` }
}
class Circle extends Shape {
  constructor(public r: number) { super('circle') }
  get area(): number { return Math.PI * this.r * this.r }
}
class Rect extends Shape {
  constructor(public w: number, public h: number) { super('rect') }
  get area(): number { return this.w * this.h }
  describe(): string { return super.describe() + ' (' + this.w + 'x' + this.h + ')' }
}
class Square extends Rect {
  constructor(s: number) { super(s, s); this.name = 'square' }
  get side(): number { return this.w }
}
let total = 0, chars = 0
for (let r = 0; r < 20; r++) {
  const shapes: Shape[] = []
  for (let i = 0; i < 5000; i++) shapes.push(i % 3 === 0 ? new Circle(i % 10 + 1) : i % 3 === 1 ? new Rect(i % 7 + 1, i % 5 + 1) : new Square(i % 9 + 1))
  let area = 0, squares = 0
  for (const s of shapes) {
    area += s.area
    if (s instanceof Square) squares += s.side
    if (s instanceof Rect) chars += s.describe().length
    else chars += s.label.length
  }
  total += Math.round(area) + squares
}
console.log(total, chars, Shape.made)
