package fixture;

class Interfaces {
	interface Shape {
		double area();
		default String describe() {
			return name() + " " + area();
		}
		private String name() {
			return getClass().getSimpleName().toLowerCase();
		}
		static Shape square(double s) {
			return () -> s * s;
		}
	}

	interface Named {
		default String describe() {
			return "named";
		}
	}

	static class Circle implements Shape {
		public double area() {
			return 3.0;
		}
	}

	static class Both implements Shape, Named {
		public double area() {
			return 1;
		}
		public String describe() {
			return Shape.super.describe() + "+" + Named.super.describe();
		}
	}

	static abstract class Base {
		abstract int value();
		int twice() {
			return value() * 2;
		}
	}

	static void run() {
		Main.say("interfaces: " + new Circle().describe());
		Main.say("interfaces: " + Shape.square(2).area());
		Main.say("interfaces: " + new Both().describe());
		Base b = new Base() {
			int value() {
				return 21;
			}
		};
		Main.say("interfaces: " + b.twice() + " " + (b instanceof Base));
		Object o = "s";
		try {
			Integer i = (Integer) o;
			Main.say("interfaces: no cast error " + i);
		} catch (ClassCastException e) {
			Main.say("interfaces: cast");
		}
		CharSequence cs = "chars";
		Main.say("interfaces: " + cs.length() + " " + cs.toString().equals("chars"));
	}
}
