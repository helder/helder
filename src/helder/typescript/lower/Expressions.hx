package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import hxmc.ir.Ir;
import haxe.ds.Vector;
import helder.typescript.ir.Builder;
import helder.typescript.check.Types;
import helder.typescript.lower.Classes.ClassLayout;
import helder.typescript.lower.Reps.ObjectLayout;
import helder.typescript.lower.Api;
import helder.typescript.lower.Core;
import helder.typescript.lower.Core.*;

// Expressions: operators, assignments, object literals, calls and
// constructions, optional chains and spreads.
@:access(helder.typescript.lower.Core)
abstract class Expressions extends Statements {
	// (a call, a construction, a property read, an await: where its frame is
	// when what it runs makes an error, V8's column; the code after it from
	// where it was before)
	function expr(n:Node):Ex {
		if (!lines && n.kind == KindNewExpression) {
			// (no table of lines: what an error made here is named by, Frames.site)
			b.runtime("libSite", [EStr(location(n))]);
			var e = expression(n);
			b.runtime("libSite", [EStr("")]);
			return e;
		}
		var site = lines ? siteOf(n) : -1;
		if (site < 0) return expression(n);
		var file = b.file, line = b.line;
		at(n, site);
		var e = switch expression(n) {
			case x = EInt(_) | EF64(_) | EStr(_) | ENull(_) | ELocal(_) | EGlobal(_) | ECast(_, EInt(_)): x;
			// (helder's API's: its call here, at its position)
			case x: Ir.typeOf(x) == TVoid ? x : b.temp(x);
		}
		if (b.line != line || b.file != file) b.mark(file, line);
		return e;
	}

	// (V8's: a call's callee or its method's name, a property's name, an element's `[`)
	static function siteOf(n:Node):Int
		return switch n.kind {
			case KindCallExpression:
				var callee = strip(n.expression());
				callee.kind == KindPropertyAccessExpression ? callee.name().pos : callee.pos;
			case KindPropertyAccessExpression: n.name().pos;
			case KindElementAccessExpression: n.expression().end;
			case KindNewExpression | KindAwaitExpression | KindYieldExpression | KindTaggedTemplateExpression: n.pos;
			case _: -1;
		}

	function expression(n:Node):Ex {
		expressions++;
		// (a dev build's live literal, an attribute's branch: its slot's read, Tsx.liveIn)
		if (tsx != null && (n.kind == KindStringLiteral || n.kind == KindNumericLiteral)) {
			var l = tsx.lives.get(Tsx.key(n));
			if (l != null) return tsx.liveRead(n, l);
		}
		var x = api == null ? null : apiExpr(n);
		if (x != null) return x;
		// (helder/native/platform's constants, and conditions of them: a literal)
		var k:Dynamic = n.kind == KindPropertyAccessExpression || n.kind == KindBinaryExpression || n.kind == KindPrefixUnaryExpression ? platform.constant(n) : null;
		if (k != null) return Std.isOfType(k, Bool) ? ECast(TBool, EInt(k ? 1 : 0)) : EStr(k);
		if (Platform.bare(n)) fail(n, "helder/native/platform's platform is the build's constants: read its fields (platform.os, platform.target, platform.arm)");
		var result:Ex = switch (n.kind) {
			case KindPropertyAccessExpression | KindElementAccessExpression | KindCallExpression if (chainTop(n)): optionalChain(n);
			case KindNumericLiteral: EF64(Std.parseFloat(n.text));
			case KindStringLiteral | KindNoSubstitutionTemplateLiteral: EStr(n.text);
			case KindTrueKeyword: ECast(TBool, EInt(1));
			case KindFalseKeyword: ECast(TBool, EInt(0));
			case KindNullKeyword: ENull(TRef(RAny));
			case KindThisKeyword: env.exists("this") ? read(env.get("this")) : b.runtime("getUndefined", []);
			case KindArrowFunction | KindFunctionExpression: closure(n, takeName());
			case KindClassExpression: classValue(n, takeName());
			case KindMetaProperty: env.exists("%newTarget") ? read(env.get("%newTarget")) : b.runtime("getUndefined", []);
			case KindNewExpression: construct(n);
			case KindIdentifier:
				var name = n.text;
				if (name == "undefined") b.runtime("getUndefined", []);
				else if (name == "NaN") EF64(Math.NaN);
				else if (name == "Infinity") EF64(Math.POSITIVE_INFINITY);
				else if (!env.exists(name) && functions.exists(name)) read(functionValues.get(name));
				// (in a namespace, a member exported by another declaration of it)
				else if (!env.exists(name) && env.exists("%namespace")) b.runtime("libNamespaceGet", [read(env.get("%namespace")), EStr(name)]);
				else if (!env.exists(name)) b.runtime("libGlobal", [EStr(name)]);
				else read(get(name, n));
			case KindParenthesizedExpression | KindAsExpression | KindTypeAssertionExpression | KindNonNullExpression | KindSatisfiesExpression: expr(n.expression());
			case KindBinaryExpression: binary(n);
			case KindPrefixUnaryExpression:
				var u = n;
				var x:Ex;
				if (u.unaryOperator() == KindPlusPlusToken || u.unaryOperator() == KindMinusMinusToken) {
					var target = numberElement(strip(u.operand())) ? numberTarget(strip(u.operand())) : lvalue(u.operand());
					x = b.temp(EBin(u.unaryOperator() == KindPlusPlusToken ? FAdd : FSub, b.coerce(target.read(), TF64), EF64(1)));
					target.write(x);
				}
				else x = u.unaryOperator() == KindMinusToken || u.unaryOperator() == KindPlusToken ? numeric(u.operand(), false) : expr(u.operand());
				switch (u.unaryOperator()) {
					// (ToNumber: a boolean's or a string's value, not its reference unboxed)
					case KindMinusToken: EConv(FNeg, number(x));
					case KindPlusToken: number(x);
					case KindExclamationToken: ENot(truth(x));
					case KindPlusPlusToken | KindMinusMinusToken: x;
					case KindTildeToken: EConv(I2F, EBin(Xor, b.runtime("libInt", [any(x)]), EInt(-1)));
					case _: fail(n, "unsupported unary operator");
				}
			case KindPostfixUnaryExpression:
				var u = n;
				var target = numberElement(strip(u.operand())) ? numberTarget(strip(u.operand())) : lvalue(u.operand());
				var previous = b.temp(b.coerce(target.read(), TF64));
				target.write(EBin(u.unaryOperator() == KindPlusPlusToken ? FAdd : FSub, previous, EF64(1)));
				previous;
			case KindVoidExpression:
				expr(n.expression());
				b.runtime("getUndefined", []);
			case KindTaggedTemplateExpression:
				var t = n;
				var template = t.template();
				var parts = template.kind == KindNoSubstitutionTemplateLiteral ? [template] : [template.head()].concat([for (span in template.templateSpans()) span.literal()]);
				var values = template.kind == KindNoSubstitutionTemplateLiteral ? [] : [for (span in template.templateSpans()) span.expression()];
				// (one frozen strings array per call site, created on first use)
				var site = global("%template" + serial++);
				b.out.push(SIf(ENot(b.runtime("libIsObject", [read(site)])), b.block(() -> set(site, b.runtime("libTemplateObject", [pack([for (x in parts) EStr(x.text)]), pack([for (x in parts) EStr(x.kind == KindNoSubstitutionTemplateLiteral ? x.rawText() : x.rawText())])]))), new Vector(0)));
				var tag = t.tag();
				while (tag.kind == KindParenthesizedExpression) tag = tag.expression();
				if ((tag.kind == KindPropertyAccessExpression || tag.kind == KindElementAccessExpression) && tag.expression().kind != KindSuperKeyword) {
					var obj = b.temp(any(expr(tag.expression())));
					var key = tag.kind == KindPropertyAccessExpression ? EStr(tag.name().text) : any(expr(tag.argumentExpression()));
					b.runtime("libCallMethod", [obj, key, pack([read(site)].concat(actuals(values)))]);
				}
				else {
					var fn = any(expr(t.tag()));
					b.runtime("libCall", [fn, b.runtime("getUndefined", []), pack([read(site)].concat(actuals(values)))]);
				}
			case KindRegularExpressionLiteral:
				var text = n.text;
				var slash = text.lastIndexOf("/");
				// (one tsgo accepts and the runtime would not: refused here, not thrown when it runs)
				var problem = helder.typescript.js.Regex.check(text.substring(1, slash), text.substr(slash + 1));
				if (problem != null) fail(n, "Invalid regular expression: " + text + ": " + problem + " (helder's RegExp does not support it)");
				b.runtime("libRegExp", [EStr(text.substring(1, slash)), EStr(text.substr(slash + 1))]);
			case KindYieldExpression:
				if (b.resumable == null || !b.resumable.generator) fail(n, "yield outside a generator");
				if (n.asteriskToken() != null) {
					if (b.resumable.async) fail(n, "yield* in async generators is not implemented yet");
					delegate(any(expr(n.expression())));
				}
				else {
					var v = n.expression() == null ? b.runtime("getUndefined", []) : any(expr(n.expression()));
					// (an async generator awaits what it yields)
					if (b.resumable.async) v = yieldPoint(v, true, AWAIT);
					yieldPoint(v, true);
				}
			case KindAwaitExpression:
				if (b.resumable == null || !b.resumable.async) fail(n, "await outside an async function");
				yieldPoint(any(expr(n.expression())), true, AWAIT, "async " + b.f.display + " (" + location(n) + ")");
			case KindTemplateExpression:
				var pieces = [EStr(n.head().text)];
				for (span in n.templateSpans()) {
					pieces.push(piece(text(expr(span.expression()))));
					pieces.push(EStr(span.literal().text));
				}
				join(pieces);
			case KindTypeOfExpression:
				var value = n.expression();
				while (value.kind == KindParenthesizedExpression) value = value.expression();
				if (value.kind == KindIdentifier && !env.exists(value.text) && !functions.exists(value.text)) {
					env.exists("%namespace") ? b.runtime("libTypeofNamespace", [read(env.get("%namespace")), EStr(value.text)]) : b.runtime("libTypeofGlobal", [EStr(value.text)]);
				}
				else b.runtime("typeOf", [any(expr(value))]);
			case KindCallExpression: call(n);
			case KindArrayLiteralExpression if (numberLiteral(n)):
				typedOperations++;
				var xs = [for (e in elements(n)) expr(e)];
				xs.filter(x -> Ir.typeOf(x) != TF64).length == 0 ? reps.numberArray(b, xs) : ECast(TRef(RObj(reps.arrayClass)), b.runtime("libArrayNumbers", [pack(xs)]));
			case KindArrayLiteralExpression:
				if (hasSpread(elements(n))) b.runtime("libArray", [spreadList(elements(n))]);
				else b.runtime("libArray", [pack([for (e in elements(n)) e.kind == KindOmittedExpression ? b.runtime("libHole", []) : expr(e)])]);
			case KindElementAccessExpression if (n.expression().kind == KindSuperKeyword):
				b.runtime("libSuperGet", [read(get("%home", n)), thisValue(), any(expr(n.argumentExpression()))]);
			case KindElementAccessExpression if (arrayElement(n)):
				var obj = b.temp(expr(n.expression()));
				typedOperations++;
				reps.arrayGet(b, obj, b.temp(number(expr(n.argumentExpression()))));
			case KindElementAccessExpression:
				var obj = expr(n.expression());
				chainCheck(n, obj);
				var key = expr(n.argumentExpression());
				dynamicOperations++;
				b.runtime("libGet", [any(obj), any(key)]);
			case KindObjectLiteralExpression: objectLiteral(n);
			case KindPropertyAccessExpression if (n.expression().kind == KindSuperKeyword):
				b.runtime("libSuperGet", [read(get("%home", n)), thisValue(), EStr(n.name().text)]);
			case KindPropertyAccessExpression if (n.name().kind == KindPrivateIdentifier):
				var a = expr(n.expression());
				chainCheck(n, a);
				b.runtime("libPrivateGet", [any(a), EStr(brand(n.name()))]);
			case KindPropertyAccessExpression if (n.name().text == "length" && plainAccess(n) && types.isString(n.expression().tsType)):
				typedOperations++;
				var s = b.temp(expr(n.expression()));
				Ir.typeOf(s).match(TRef(RStr)) ? b.runtime("stringLength", [s]) : b.coerce(b.runtime("libGet", [any(s), EStr("length")]), TF64);
			case KindPropertyAccessExpression if (n.name().text == "length" && plainAccess(n) && types.isArray(n.expression().tsType)):
				typedOperations++;
				reps.arrayLength(b, b.temp(expr(n.expression())));
			case KindPropertyAccessExpression if (layoutField(n) != null):
				typedOperations++;
				reps.fieldGet(b, layoutField(n), b.temp(expr(n.expression())), n.name().text, where());
			case KindPropertyAccessExpression:
				var a = expr(n.expression());
				var name = n.name().text;
				chainCheck(n, a);
				dynamicOperations++;
				var laid = plainAccess(n) ? reps.objectCandidates(n.expression().tsType, name) : [];
				if (laid.length == 0) reps.siteGet(b, a, name);
				else if (numberRead == n) {
					var slot = numberIntoSlot;
					numberRead = null;
					reps.objectGet(b, a, name, laid, TF64, g -> slot ? store(g, TF64) : number(g));
				}
				else reps.objectGet(b, a, name, laid, TRef(RAny), g -> g);
			case KindDeleteExpression:
				var target = n.expression();
				if (target.kind == KindPropertyAccessExpression) b.runtime("libDelete", [any(expr(target.expression())), EStr(target.name().text)]);
				else if (target.kind == KindElementAccessExpression) {
					var obj = expr(target.expression());
					b.runtime("libDelete", [any(obj), any(expr(target.argumentExpression()))]);
				}
				else fail(n, "delete requires a property");
			case KindConditionalExpression if (platform.constant(n.condition()) != null):
				// (a platform's constant: only the branch taken)
				expr(Platform.truthy(platform.constant(n.condition())) ? n.whenTrue() : n.whenFalse());
			case KindConditionalExpression:
				var c = n;
				var cond = truth(expr(c.condition()));
				var l = b.local("conditional", loose(n) ? TRef(RAny) : reps.rep(n.tsType));
				var yes = b.block(() -> b.out.push(SSet(l, store(valueFor(c.whenTrue(), l.ty), l.ty))));
				var no = b.block(() -> b.out.push(SSet(l, store(valueFor(c.whenFalse(), l.ty), l.ty))));
				b.out.push(SIf(cond, yes, no));
				ELocal(l);
			case _: fail(n, "unsupported expression " + n.kind.toString());
		};
		if (Ir.typeOf(result).match(TRef(RAny))) dynamicSites++; else typed++;
		return switch (result) {
			case EInt(_) | EF64(_) | EStr(_) | ENull(_) | ELocal(_): result;
			case _: b.temp(result);
		};
	}

	function lvalue(n:Node):{read:() -> Ex, write:Ex->Void} {
		while (n.kind == KindParenthesizedExpression || n.kind == KindNonNullExpression || n.kind == KindAsExpression || n.kind == KindSatisfiesExpression || n.kind == KindTypeAssertionExpression) n = n.expression();
		var member = api == null ? null : apiTarget(n);
		if (member != null) return member;
		if (n.kind == KindIdentifier) {
			var v = get(n.text, n);
			return {read: () -> b.temp(read(v)), write: (e) -> set(v, e)};
		}
		if ((n.kind == KindPropertyAccessExpression || n.kind == KindElementAccessExpression) && n.expression().kind == KindSuperKeyword) {
			var key = n.kind == KindPropertyAccessExpression ? EStr(n.name().text) : b.temp(any(expr(n.argumentExpression())));
			var home = read(get("%home", n));
			return {
				read: () -> b.runtime("libSuperGet", [home, thisValue(), key]),
				write: (e) -> {
					b.runtime("libSuperSet", [home, thisValue(), key, any(e)]);
				}
			};
		}
		if (n.kind == KindPropertyAccessExpression && n.name().kind == KindPrivateIdentifier) {
			var obj = b.temp(any(expr(n.expression())));
			var key = EStr(brand(n.name()));
			return {
				read: () -> b.runtime("libPrivateGet", [obj, key]),
				write: (e) -> {
					b.runtime("libPrivateSet", [obj, key, any(e)]);
				}
			};
		}
		if (arrayElement(n)) {
			var obj = b.temp(expr(n.expression()));
			var key = b.temp(number(expr(n.argumentExpression())));
			var numbers = numberElement(n);
			return {
				read: () -> reps.arrayGet(b, obj, key),
				write: (e) -> numbers && Ir.typeOf(e) == TF64 ? reps.arraySetNumber(b, obj, key, e) : reps.arraySet(b, obj, key, e)
			};
		}
		var field = layoutField(n);
		if (field != null) {
			var obj = b.temp(expr(n.expression()));
			var name = n.name().text;
			return {
				read: () -> reps.fieldGet(b, field, obj, name, where()),
				write: (e) -> reps.fieldSet(b, field, obj, name, e, where())
			};
		}
		if (n.kind == KindPropertyAccessExpression) {
			var obj = b.temp(any(expr(n.expression())));
			var name = n.name().text;
			var laid = plainAccess(n) ? reps.objectCandidates(n.expression().tsType, name) : [];
			if (laid.length > 0) return {
				read: () -> reps.objectGet(b, obj, name, laid, TRef(RAny), g -> g),
				write: (e) -> reps.objectSet(b, obj, name, laid, e)
			};
			return {
				read: () -> reps.siteGet(b, obj, name),
				write: (e) -> reps.sitePut(b, obj, name, e)
			};
		}
		if (n.kind == KindElementAccessExpression) {
			var obj = expr(n.expression());
			var key = expr(n.argumentExpression());
			return {
				read: () -> b.runtime("libGet", [any(obj), any(key)]),
				write: (e) -> {
					b.runtime("libPut", [any(obj), any(key), any(e)]);
				}
			};
		}
		return fail(n, "unsupported assignment target");
	}

	function strictEquals(a:Ex, z:Ex):Ex return equals(a, z, true);

	// (a null or undefined literal: which)
	function nullish(n:Node):Null<String> {
		while (n.kind == KindParenthesizedExpression) n = n.expression();
		return n.kind == KindNullKeyword ? "null" : n.kind == KindIdentifier && n.text == "undefined" && !env.exists("undefined") ? "undefined" : null;
	}

	// whether a value is null, undefined, or (which: null) either: by reference
	function isNullish(e:Ex, which:Null<String>):Ex {
		var v = b.temp(any(e));
		var isNull = EBin(RefEq, v, ENull(TRef(RAny))), isUndefined = EBin(RefEq, v, b.runtime("getUndefined", []));
		typedOperations++;
		if (which == "null") return isNull;
		if (which == "undefined") return isUndefined;
		var l = b.local("nullish", TBool);
		b.out.push(SSet(l, isNull));
		b.out.push(SIf(ENot(ELocal(l)), Vector.fromArrayCopy([SSet(l, isUndefined)]), new Vector(0)));
		return ELocal(l);
	}

	function equals(a:Ex, z:Ex, strict:Bool):Ex {
		var direct:Ex = null;
		if (Ir.typeOf(a) == TF64 && Ir.typeOf(z) == TF64) direct = EBin(FEq, a, z);
		if (Ir.typeOf(a) == TBool && Ir.typeOf(z) == TBool) direct = EBin(Eq, a, z);
		if (Ir.typeOf(a).match(TRef(RStr)) && Ir.typeOf(z).match(TRef(RStr))) direct = b.runtime("stringEq", [a, z]);
		if (direct != null) {
			typedOperations++;
			return direct;
		}
		dynamicOperations++;
		return b.runtime(strict ? "strictEq" : "looseEq", [any(a), any(z)]);
	}

	function binary(n:Node):Ex {
		var x = n;
		var op = x.operatorToken().kind;
		if (op == KindCommaToken) {
			expr(x.left());
			return expr(x.right());
		}
		if (op >= KindFirstAssignment && op <= KindLastAssignment) return assign(n);
		if (op == KindInKeyword && x.left().kind == KindPrivateIdentifier) return b.runtime("libPrivateHas", [any(expr(x.right())), EStr(brand(x.left()))]);
		// (a loop counter's remainder: on its Int64)
		if (op == KindPercentToken && intOf(x.left()) != null) {
			typedOperations++;
			var counter = intOf(x.left());
			var divisor = intOf(x.right());
			return divisor != null ? remainderInt(counter, divisor) : remainderOf(counter, numeric(x.right(), false));
		}
		var relation = op == KindLessThanToken || op == KindLessThanEqualsToken || op == KindGreaterThanToken || op == KindGreaterThanEqualsToken;
		if (relation && numericOperator(op, n) && (laidNumber(x.left()) || laidNumber(x.right()))) return eitherRelation(op, x.left(), x.right());
		if (op == KindPlusToken && numericOperator(op, n) && laidSum(n)) {
			var e = eitherSum(n);
			var v = b.local("sum", TRef(RAny));
			b.out.push(SIf(ELocal(e.num), b.block(() -> b.out.push(SSet(v, any(ELocal(e.f))))), b.block(() -> b.out.push(SSet(v, e.any())))));
			return ELocal(v);
		}
		if (op == KindPlusToken && !numericOperator(op, n)) {
			var pieces = plusPieces(n);
			return pieces.length == 1 ? pieces[0] : join(pieces);
		}
		var coerce = op != KindPlusToken && !relation;
		var a = numericOperator(op, n) ? numeric(x.left(), false, coerce) : expr(x.left());
		if (op == KindAmpersandAmpersandToken || op == KindBarBarToken || op == KindQuestionQuestionToken) {
			// (the result, the left or the right value, in a slot of the expression's type)
			var l = b.local("shortCircuit", loose(n) ? TRef(RAny) : reps.rep(n.tsType));
			var right = op == KindQuestionQuestionToken ? isNullish(a, null) : op == KindBarBarToken ? ENot(truth(a)) : truth(a);
			var lhs = b.block(() -> b.out.push(SSet(l, store(a, l.ty))));
			var rhs = b.block(() -> b.out.push(SSet(l, store(expr(x.right()), l.ty))));
			b.out.push(SIf(right, rhs, lhs));
			return ELocal(l);
		}
		if (op == KindInstanceOfKeyword) return b.runtime("libInstanceOf", [any(a), any(expr(x.right()))]);
		return operate(op, a, numericOperator(op, n) ? numeric(x.right(), false, coerce) : expr(x.right()), n);
	}

	// (a property read whose object layouts' slot is a number: Reps.objectGetEither)
	function laidNumber(n:Node):Bool {
		var inner = strip(n);
		while (inner.kind == KindNonNullExpression) inner = strip(inner.expression());
		if (inner.kind != KindPropertyAccessExpression || !plainAccess(inner) || inner.name().kind != KindIdentifier || !types.isNumber(inner.tsType)) return false;
		var name = inner.name().text;
		return Lambda.exists(reps.objectCandidates(inner.expression().tsType, name), c -> c.tys[c.names.indexOf(name)] == TF64);
	}

	// (a sum of numbers, + of + ..., one of whose terms is such a read)
	function laidSum(n:Node):Bool {
		var inner = strip(n);
		if (laidNumber(inner)) return true;
		return inner.kind == KindBinaryExpression && inner.operatorToken().kind == KindPlusToken && numericOperator(KindPlusToken, inner)
			&& (laidSum(inner.left()) || laidSum(inner.right()));
	}

	// a sum of numbers computed unboxed while each term is a number (a read
	// of an object layout's slot, or a value that is one), else as + does:
	// the sum is boxed once where it is a value, not each term
	function eitherSum(n:Node):{num:Local, f:Local, any:() -> Ex} {
		var inner = strip(n);
		var num = b.local("isNumber", TBool), f = b.local("number", TF64);
		if (inner.kind == KindBinaryExpression && inner.operatorToken().kind == KindPlusToken && numericOperator(KindPlusToken, inner)) {
			var a = eitherSum(inner.left()), z = eitherSum(inner.right());
			b.out.push(SSet(num, bool(false)));
			b.out.push(SIf(ELocal(a.num), b.block(() -> b.out.push(SIf(ELocal(z.num), b.block(() -> {
				b.out.push(SSet(f, EBin(FAdd, ELocal(a.f), ELocal(z.f))));
				b.out.push(SSet(num, bool(true)));
			}), new Vector(0)))), new Vector(0)));
			return {num: num, f: f, any: () -> b.runtime("add", [a.any(), z.any()])};
		}
		if (laidNumber(inner)) {
			while (inner.kind == KindNonNullExpression) inner = strip(inner.expression());
			var o = expr(inner.expression()), name = inner.name().text;
			var e = reps.objectGetEither(b, o, name, reps.objectCandidates(inner.expression().tsType, name));
			return {num: e.num, f: e.f, any: () -> {
				var v = b.local("term", TRef(RAny));
				b.out.push(SIf(ELocal(e.num), b.block(() -> b.out.push(SSet(v, any(ELocal(e.f))))), b.block(() -> b.out.push(SSet(v, ELocal(e.any))))));
				return ELocal(v);
			}};
		}
		var e = b.temp(expr(n));
		if (Ir.typeOf(e) == TF64) {
			b.out.push(SSet(num, bool(true)));
			b.out.push(SSet(f, e));
			return {num: num, f: f, any: () -> any(e)};
		}
		var v = b.temp(any(e));
		b.out.push(SSet(num, b.runtime("libIsNumber", [v])));
		b.out.push(SIf(ELocal(num), b.block(() -> b.out.push(SSet(f, b.runtime("libNumber", [v])))), new Vector(0)));
		return {num: num, f: f, any: () -> v};
	}

	// a relation of numbers one of which is such a read: unboxed where both
	// are numbers, else the relation of their values (strings compare as strings)
	function eitherRelation(op:Kind, left:Node, right:Node):Ex {
		function operand(n:Node):{num:Ex, f:Ex, any:() -> Ex} {
			if (laidNumber(n)) {
				var inner = strip(n);
				while (inner.kind == KindNonNullExpression) inner = strip(inner.expression());
				var o = expr(inner.expression()), name = inner.name().text;
				var e = reps.objectGetEither(b, o, name, reps.objectCandidates(inner.expression().tsType, name));
				return {num: ELocal(e.num), f: ELocal(e.f), any: () -> {
					var v = b.local("operand", TRef(RAny));
					b.out.push(SIf(ELocal(e.num), b.block(() -> b.out.push(SSet(v, any(ELocal(e.f))))), b.block(() -> b.out.push(SSet(v, ELocal(e.any))))));
					return ELocal(v);
				}};
			}
			var e = b.temp(expr(n));
			return Ir.typeOf(e) == TF64 ? {num: bool(true), f: e, any: () -> any(e)} : {num: bool(false), f: EF64(0), any: () -> any(e)};
		}
		var a = operand(left), z = operand(right);
		var r = b.local("relation", TBool);
		var bin:BinOp = op == KindLessThanToken ? FLt : op == KindLessThanEqualsToken ? FLe : op == KindGreaterThanToken ? FGt : FGe;
		var text = op == KindLessThanToken ? "<" : op == KindLessThanEqualsToken ? "<=" : op == KindGreaterThanToken ? ">" : ">=";
		typedOperations++;
		var both = b.local("numbers", TBool);
		b.out.push(SSet(both, bool(false)));
		b.out.push(SIf(a.num, b.block(() -> b.out.push(SIf(z.num, Vector.fromArrayCopy([SSet(both, bool(true))]), new Vector(0)))), new Vector(0)));
		b.out.push(SIf(ELocal(both), b.block(() -> b.out.push(SSet(r, EBin(bin, a.f, z.f)))),
			b.block(() -> b.out.push(SSet(r, b.runtime("libRelation", [a.any(), z.any(), EStr(text)]))))));
		return ELocal(r);
	}
	// a chain of + making a string: its operands' text in order, joined once
	// rather than a concat each; the first two made text after both are
	// evaluated, the others right after their own (as each + does)
	function plusPieces(n:Node):Array<Ex> {
		var l = n.left();
		while (l.kind == KindParenthesizedExpression) l = l.expression();
		var chain = l.kind == KindBinaryExpression && l.operatorToken().kind == KindPlusToken && !numericOperator(KindPlusToken, l);
		var left = chain ? plusPieces(l) : [expr(l)];
		var z = expr(n.right());
		if (left.length > 1) return left.concat([piece(plusText(z))]);
		var a = left[0];
		if (!Ir.typeOf(a).match(TRef(RStr)) && !Ir.typeOf(z).match(TRef(RStr))) return [operate(KindPlusToken, a, z, n)];
		return [piece(plusText(a)), piece(plusText(z))];
	}

	function assign(n:Node):Ex {
		var x = n;
		var op = x.operatorToken().kind;
		var left = x.left();
		while (left.kind == KindParenthesizedExpression) left = left.expression();
		if (op == KindPlusEqualsToken && left.kind == KindIdentifier && env.exists(left.text) && env.get(left.text).buffer != null) {
			b.runtime("libBufferAdd", [ELocal(env.get(left.text).buffer), plusText(expr(x.right()))]);
			return b.runtime("getUndefined", []);
		}
		if (op == KindEqualsToken && (left.kind == KindArrayLiteralExpression || left.kind == KindObjectLiteralExpression)) {
			var e = b.temp(any(expr(x.right())));
			assignPattern(left, e);
			return e;
		}
		var source = strip(x.right());
		while (source.kind == KindNonNullExpression) source = strip(source.expression());
		if (op == KindEqualsToken && numberElement(left) && numberElement(source)) {
			// (a[i] = b[j] of number arrays: the number copied unboxed, else the element as it is)
			var target = lvalue(left);
			var obj = b.temp(expr(source.expression()));
			var k = intOf(source.argumentExpression()) ?? b.temp(number(expr(source.argumentExpression())));
			var boxed = b.local("copied", TRef(RAny)), missed = b.local("missed", TBool);
			b.out.push(SSet(missed, bool(false)));
			var v = reps.arrayGetNumber(b, obj, k, g -> {
				b.out.push(SSet(boxed, any(g)));
				b.out.push(SSet(missed, bool(true)));
				return EF64(0);
			});
			var used = n.parent == null || n.parent.kind != KindExpressionStatement;
			b.out.push(SIf(ELocal(missed), b.block(() -> target.write(ELocal(boxed))), b.block(() -> {
				target.write(v);
				if (used) b.out.push(SSet(boxed, any(v)));
			})));
			return used ? ELocal(boxed) : b.runtime("getUndefined", []);
		}
		var arithmetic = op != KindEqualsToken && compound.exists(op) && numericOperator(compound.get(op), n);
		var target = arithmetic && numberElement(left) ? numberTarget(left) : lvalue(x.left());
		if (op == KindEqualsToken) {
			var e = numberSlot(left) ? numeric(x.right(), true) : named(x.right(), left.kind == KindIdentifier ? left.text : null);
			target.write(e);
			return e;
		}
		if (op == KindBarBarEqualsToken || op == KindAmpersandAmpersandEqualsToken || op == KindQuestionQuestionEqualsToken) {
			// (the right side is evaluated and stored only when it is needed)
			var previous = target.read();
			var l = b.local("logical", TRef(RAny));
			b.out.push(SSet(l, any(previous)));
			var cond = op == KindQuestionQuestionEqualsToken ? b.runtime("looseEq", [any(previous), ENull(TRef(RAny))]) : op == KindBarBarEqualsToken ? ENot(truth(previous)) : truth(previous);
			b.out.push(SIf(cond, b.block(() -> {
				var e = expr(x.right());
				target.write(e);
				b.out.push(SSet(l, any(e)));}), new Vector(0)));
			return ELocal(l);
		}
		var previous = target.read();
		// (+= into a number's slot: the sum is stored as a number, so a value that is none stops there, as store does)
		var plus = compound.get(op) == KindPlusToken;
		var e = operate(compound.get(op), previous, arithmetic ? numeric(x.right(), plus && Ir.typeOf(previous) == TF64, !plus) : expr(x.right()), n);
		target.write(e);
		return e;
	}

	function operate(op:Kind, a:Ex, z:Ex, n:Node):Ex {
		if (op == KindInKeyword) return b.runtime("libHas", [any(z), any(a)]);
		if (op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken || op == KindEqualsEqualsToken || op == KindExclamationEqualsToken) {
			var strict = op == KindEqualsEqualsEqualsToken || op == KindExclamationEqualsEqualsToken;
			var literal = n.kind == KindBinaryExpression ? nullish(n.left()) ?? nullish(n.right()) : null;
			var e = literal != null ? isNullish(nullish(n.left()) != null ? z : a, strict ? literal : null) : equals(a, z, strict);
			return op == KindExclamationEqualsEqualsToken || op == KindExclamationEqualsToken ? ENot(e) : e;
		}
		if (op == KindPlusToken && (Ir.typeOf(a).match(TRef(RStr)) || Ir.typeOf(z).match(TRef(RStr)))) return b.runtime("concat", [plusText(a), plusText(z)]);
		if (op == KindPlusToken && (Ir.typeOf(a).match(TRef(RAny)) || Ir.typeOf(z).match(TRef(RAny)))) return b.runtime("add", [any(a), any(z)]);
		var relation = op == KindLessThanToken || op == KindLessThanEqualsToken || op == KindGreaterThanToken || op == KindGreaterThanEqualsToken;
		if (relation && !(Ir.typeOf(a) == TF64 && Ir.typeOf(z) == TF64)) {
			dynamicOperations++;
			return b.runtime("libRelation", [any(a), any(z), EStr(op == KindLessThanToken ? "<" : op == KindLessThanEqualsToken ? "<=" : op == KindGreaterThanToken ? ">" : ">=")]);
		}
		if (op == KindAmpersandToken || op == KindBarToken || op == KindCaretToken || op == KindLessThanLessThanToken || op == KindGreaterThanGreaterThanToken || op == KindGreaterThanGreaterThanGreaterThanToken) {
			// (a number's ToInt32 without boxing it)
			function int32(x:Ex) return Ir.typeOf(x) == TF64 ? b.runtime("numberInt32", [x]) : b.runtime("libInt", [any(x)]);
			var left = int32(a), right = int32(z);
			var value = EBin(op == KindAmpersandToken ? And : op == KindBarToken ? Or : op == KindCaretToken ? Xor : op == KindLessThanLessThanToken ? Shl : op == KindGreaterThanGreaterThanToken ? Shr : UShr, left, right);
			return op == KindGreaterThanGreaterThanGreaterThanToken ? b.runtime("libUnsigned", [b.temp(value)]) : EConv(I2F, value);
		}
		typedOperations++;
		if (op == KindPercentToken) return remainder(a, z);
		if (op == KindAsteriskAsteriskToken) return b.runtime("power", [b.coerce(a, TF64), b.coerce(z, TF64)]);
		var bin:BinOp = switch (op) {
			case KindPlusToken: FAdd;
			case KindMinusToken: FSub;
			case KindAsteriskToken: FMul;
			case KindSlashToken: FDiv;
			case KindPercentToken: FMod;
			case KindLessThanToken: FLt;
			case KindLessThanEqualsToken: FLe;
			case KindGreaterThanToken: FGt;
			case KindGreaterThanEqualsToken: FGe;
			case _: return fail(n, "unsupported binary operator " + op.toString());
		};
		return EBin(bin, b.coerce(a, TF64), b.coerce(z, TF64));
	}

	// `x % c` for a literal integer divisor. Integral dividends below 2^31 in
	// magnitude take a multiply-and-shift quotient (Granlund-Montgomery, as
	// optimizing JS engines do; exact over that range) instead of a hardware
	// division; others take exact binary long division. Both are inline: a call
	// in a loop makes hxmc keep the loop's variables in memory. Variable
	// divisors go through the runtime's JS-exact helper.
	// x % c of an Int64 x (a loop counter: below 2^53 in magnitude): for a
	// literal c, x's magnitude below 2^31, a multiply and shift as remainder's;
	// else remainder's on x's double
	function remainderOf(x:Ex, z:Ex):Ex {
		var c = switch (z) {
			case EF64(v) if (v >= 1 && v <= 2147483647 && Math.ffloor(v) == v): Std.int(v);
			case _: return remainder(b.temp(EConv(L2F, x)), z);
		};
		var shift = 31;
		while (Math.pow(2, shift - 31) < c) shift++;
		var m = Math.ffloor(Math.pow(2, shift) / c) + 1;
		var high = Std.int(Math.ffloor(m / 4294967296.0)), low = Std.int(m - high * 4294967296.0);
		var mLong = EBin(LOr, EBin(LShl, EConv(I2L, EInt(high)), EInt(32)), EBin(LAnd, EConv(I2L, EInt(low)), EBin(LUShr, EConv(I2L, EInt(-1)), EInt(32))));
		var l = b.local("remainder", TF64);
		var negative = EBin(LLt, x, EConv(I2L, EInt(0)));
		var magnitude = b.local("magnitude", TI64);
		b.out.push(SIf(negative, Vector.fromArrayCopy([SSet(magnitude, EBin(LSub, EConv(I2L, EInt(0)), x))]), Vector.fromArrayCopy([SSet(magnitude, x)])));
		b.out.push(SIf(EBin(LLt, ELocal(magnitude), EBin(LShl, EConv(I2L, EInt(1)), EInt(31))), b.block(() -> {
			var q = b.temp(EBin(LShr, EBin(LMul, ELocal(magnitude), mLong), EInt(shift)));
			var r = b.temp(EConv(L2F, EBin(LSub, ELocal(magnitude), EBin(LMul, q, EConv(I2L, EInt(c))))));
			// (the dividend's sign, -0 included)
			b.out.push(SIf(negative, Vector.fromArrayCopy([SSet(l, EConv(FNeg, r))]), Vector.fromArrayCopy([SSet(l, r)])));
		}), b.block(() -> b.out.push(SSet(l, remainder(b.temp(EConv(L2F, x)), z))))));
		return ELocal(l);
	}

	// x % y of two Int64s (loop counters): the truncated remainder, the dividend's sign (-0 included); NaN for y 0
	function remainderInt(x:Ex, y:Ex):Ex {
		var l = b.local("remainder", TF64);
		var zero = EConv(I2L, EInt(0));
		b.out.push(SIf(EBin(LEq, y, zero), Vector.fromArrayCopy([SSet(l, EF64(Math.NaN))]), b.block(() -> {
			var r = b.temp(EConv(L2F, EBin(LMod, x, y)));
			b.out.push(SSet(l, r));
			// (a zero remainder of a negative dividend is -0)
			b.out.push(SIf(EBin(LLt, x, zero), Vector.fromArrayCopy([SIf(EBin(FEq, r, EF64(0)), Vector.fromArrayCopy([SSet(l, EConv(FNeg, EF64(0)))]), new Vector(0))]), new Vector(0)));
		})));
		return ELocal(l);
	}

	function remainder(a:Ex, z:Ex):Ex {
		var x = b.temp(b.coerce(a, TF64));
		var c = switch (z) {
			case EF64(v) if (v >= 1 && v <= 2147483647 && Math.ffloor(v) == v): Std.int(v);
			case _: return b.runtime("modulo", [x, b.coerce(z, TF64)]);
		};
		var shift = 31;
		while (Math.pow(2, shift - 31) < c) shift++;
		var m = Math.ffloor(Math.pow(2, shift) / c) + 1;
		function long(v:Float):Ex {
			var high = Std.int(Math.ffloor(v / 4294967296.0)), low = Std.int(v - high * 4294967296.0);
			return EBin(LOr, EBin(LShl, EConv(I2L, EInt(high)), EInt(32)), EBin(LAnd, EConv(I2L, EInt(low)), EBin(LUShr, EConv(I2L, EInt(-1)), EInt(32))));
		}
		function set(l:Local, e:Ex) b.out.push(SSet(l, e));
		function when(cond:Ex, then:() -> Void, ?otherwise:() -> Void) b.out.push(SIf(cond, b.block(then), otherwise == null ? new Vector(0) : b.block(otherwise)));
		function loopWhile(cond:() -> Ex, body:() -> Void) b.out.push(SLoop(b.block(() -> {
			when(ENot(cond()), () -> b.out.push(SBreak));
			body();})));
		var l = b.local("remainder", TF64), magnitude = b.local("magnitude", TF64), r = b.local("rest", TF64), done = b.local("integral", TBool);
		set(done, ECast(TBool, EInt(0)));
		when(EBin(FLt, x, EF64(0)), () -> set(magnitude, EConv(FNeg, x)), () -> set(magnitude, x));
		when(EBin(FLt, ELocal(magnitude), EF64(2147483648.0)), () -> {
			var xi = b.temp(EConv(F2L, ELocal(magnitude)));
			when(EBin(FEq, EConv(L2F, xi), ELocal(magnitude)), () -> {
				var q = b.temp(EBin(LShr, EBin(LMul, xi, long(m)), EInt(shift)));
				set(r, EConv(L2F, EBin(LSub, xi, EBin(LMul, q, EConv(I2L, EInt(c))))));
				set(done, ECast(TBool, EInt(1)));
			});
		});
		when(ENot(ELocal(done)), () -> {
			// (x-x is 0 exactly when x is finite)
			when(ENot(EBin(FEq, EBin(FSub, x, x), EF64(0))), () -> set(r, EF64(Math.NaN)), () -> {
				set(r, ELocal(magnitude));
				var t = b.local("step", TF64);
				set(t, EF64(c));
				loopWhile(() -> EBin(FLe, ELocal(t), EBin(FMul, ELocal(r), EF64(0.5))), () -> set(t, EBin(FMul, ELocal(t), EF64(2))));
				loopWhile(() -> EBin(FGe, ELocal(t), EF64(c)), () -> {
					when(EBin(FGe, ELocal(r), ELocal(t)), () -> set(r, EBin(FSub, ELocal(r), ELocal(t))));
					set(t, EBin(FMul, ELocal(t), EF64(0.5)));
				});
			});
		});
		// (the sign of the dividend, -0 included)
		when(EBin(FEq, ELocal(r), EF64(0)), () -> set(l, EBin(FMul, EF64(0), x)), () -> when(EBin(FLt, x, EF64(0)), () -> set(l, EConv(FNeg, ELocal(r))), () -> set(l, ELocal(r))));
		return ELocal(l);
	}

	function brand(name:Node):String {
		var i = privateScopes.length - 1;
		while (i >= 0) {
			var scope = privateScopes[i--];
			if (scope.exists(name.text)) return scope.get(name.text);
		}
		return fail(name, "unknown private name " + name.text);
	}

	// A property key as an expression: names and literals are strings, computed keys are evaluated.
	function memberKey(name:Node):Ex return switch (name.kind) {
		case KindComputedPropertyName: b.temp(any(expr(name.expression())));
		case KindNumericLiteral: b.temp(b.runtime("text", [any(EF64(Std.parseFloat(name.text)))]));
		case _: EStr(name.text);
	};

	// ---- object types' layouts (Reps.objectLayout)

	// (a literal's properties when each is a plain one of a static name, its
	// name distinct, not an index: their names and value nodes; else null)
	function plainMembers(props:Array<Node>):Null<Array<{name:String, value:Node}>> {
		var out = [], seen:Map<String, Bool> = [];
		for (prop in props) {
			var name = switch prop.kind {
				case KindShorthandPropertyAssignment: prop.name().text;
				case KindPropertyAssignment if (prop.name().kind == KindIdentifier || prop.name().kind == KindStringLiteral): prop.name().text;
				case _: return null;
			};
			if (name == "__proto__" || seen.exists(name) || ~/^(0|[1-9][0-9]*)$/.match(name)) return null;
			seen.set(name, true);
			out.push({name: name, value: prop.kind == KindPropertyAssignment ? prop.initializer() : prop.name()});
		}
		return out.length > 0 && out.length <= 64 ? out : null;
	}

	// (a property value's slot: as its type says)
	function slotType(value:Node):Ty return loose(value) ? TRef(RAny) : reps.rep(value.tsType);

	// (the object types a literal's values are: its own, the one it is made for)
	function made(l:ObjectLayout, n:Node) {
		var own = n.tsType, ctx = n.contextualType();
		if (own != null) l.types.set(own.id, true);
		if (ctx != null) {
			l.types.set(ctx.id, true);
			if (ctx.members != null) for (m in ctx.members) l.types.set(m.id, true);
		}
	}

	function prepareLayouts() {
		var spreads:Array<Node> = [];
		for (sf in src.files) for (i in 1...sf.count) if (sf.kindAt(i) == KindObjectLiteralExpression) {
			var n = sf.node(i);
			var props = properties(n);
			if (props.length > 1 && props[0].kind == KindSpreadAssignment) {
				spreads.push(n);
				continue;
			}
			var own = plainMembers(props);
			if (own == null) continue;
			var tys = [for (m in own) slotType(m.value)];
			// (nothing typed: nothing a layout would do better than a shape)
			if (Lambda.foreach(tys, t -> t.match(TRef(RAny)))) continue;
			var l = reps.objectLayout([for (m in own) m.name], tys);
			made(l, n);
			literalLayouts.set(n, l);
		}
		// (a spread's of a spread's, in either order: twice)
		for (round in 0...2) for (n in spreads) if (!spreadLayouts.exists(n)) {
			var props = properties(n);
			var own = plainMembers(props.slice(1));
			var from = own == null ? null : reps.objectOf(props[0].expression().tsType);
			if (from == null) continue;
			var names = from.names.copy(), tys = from.tys.copy();
			for (m in own) {
				var i = names.indexOf(m.name);
				if (i >= 0) tys[i] = slotType(m.value);
				else {
					names.push(m.name);
					tys.push(slotType(m.value));
				}
			}
			if (names.length > 64) continue;
			var to = reps.objectLayout(names, tys);
			made(to, n);
			spreadLayouts.set(n, {from: from, to: to});
		}
	}

	// (values into a layout's slots: where each fits, then with them; else otherwise)
	function intoSlots(values:Array<Ex>, tys:Array<Ty>, then:Array<Ex>->Void, otherwise:() -> Void) {
		// (each fits whatever its value: the instance alone, no join with the other way, so
		// hxmc's escape analysis may replace one that does not leave its function)
		if ([for (i in 0...values.length) i].filter(i -> !reps.fitsStatically(values[i], tys[i])).length == 0) {
			var typed:Array<Ex> = [];
			for (i in 0...values.length) reps.ifFits(b, values[i], tys[i], x -> typed.push(x), () -> {});
			then(typed);
			return;
		}
		var ok = b.local("fits", TBool);
		b.out.push(SSet(ok, bool(true)));
		var typed = [for (i in 0...values.length) {
			var l = b.local("slot", tys[i]);
			reps.ifFits(b, values[i], tys[i], x -> b.out.push(SSet(l, x)), () -> b.out.push(SSet(ok, bool(false))));
			ELocal(l);
		}];
		b.out.push(SIf(ELocal(ok), b.block(() -> then(typed)), b.block(otherwise)));
	}

	// a literal of a layout: an instance of it where its values fit, else one of its shape
	function layoutLiteral(props:Array<Node>, l:ObjectLayout):Ex {
		var own = plainMembers(props);
		var values = [for (m in own) m.value == null ? null : named(m.value, m.name)];
		var r = b.local("object", TRef(RAny));
		intoSlots(values, l.tys, typed -> b.out.push(SSet(r, any(reps.objectNew(b, l, typed)))),
			() -> b.out.push(SSet(r, b.runtime("libLiteral", [reps.literalShape(l.names), pack(values)]))));
		return ELocal(r);
	}

	// `{...x, k: v}` where x's type's values are made by one layout: where x
	// is exactly an instance of it, a new instance of the spread's layout,
	// its slots copied; else property by property
	function spreadLiteral(props:Array<Node>, from:ObjectLayout, to:ObjectLayout):Ex {
		var source = b.temp(any(expr(props[0].expression())));
		var exact = b.local("exact", TBool);
		b.out.push(SSet(exact, bool(false)));
		var copied = [for (t in from.tys) b.local("copied", t)];
		reps.exactly(b, source, from, o -> {
			for (k in 0...from.names.length) b.out.push(SSet(copied[k], EField(from.info, reps.objectSlot(from, from.names[k]), o)));
			b.out.push(SSet(exact, bool(true)));
		});
		var o = b.local("spread", TRef(RAny));
		function spread() {
			b.out.push(SSet(o, b.runtime("libObject", [pack([]), pack([])])));
			b.runtime("libAssignSpread", [ELocal(o), source]);
		}
		b.out.push(SIf(ELocal(exact), new Vector(0), b.block(spread)));
		var own = plainMembers(props.slice(1));
		var values = [for (m in own) named(m.value, m.name)];
		var r = b.local("object", TRef(RAny));
		var slots = [for (k in 0...to.names.length) {
			var i = Lambda.findIndex(own, m -> m.name == to.names[k]);
			i >= 0 ? values[i] : ELocal(copied[k]);
		}];
		function generic() {
			b.out.push(SIf(ELocal(exact), b.block(spread), new Vector(0)));
			for (k in 0...own.length) b.runtime("libDefineField", [ELocal(o), EStr(own[k].name), any(values[k])]);
			b.out.push(SSet(r, ELocal(o)));
		}
		b.out.push(SIf(ELocal(exact), b.block(() -> intoSlots(slots, to.tys, typed -> b.out.push(SSet(r, any(reps.objectNew(b, to, typed)))), generic)), b.block(generic)));
		return ELocal(r);
	}

	// Object literals: plain ones in one call; others property by property
	// (methods and accessors see the object as their home for super).
	function objectLiteral(n:Node):Ex {
		var props = properties(n);
		var laid = literalLayouts.get(n);
		if (laid != null) return layoutLiteral(props, laid);
		var spread = spreadLayouts.get(n);
		if (spread != null) return spreadLiteral(props, spread.from, spread.to);
		var plain = true;
		for (prop in props) if (!(prop.kind == KindPropertyAssignment && prop.name().kind != KindComputedPropertyName && prop.name().text != "__proto__" || prop.kind == KindShorthandPropertyAssignment)) plain = false;
		if (plain) {
			var ks:Array<String> = [], vs:Array<Ex> = [];
			for (prop in props) {
				ks.push(prop.kind == KindPropertyAssignment ? staticName(prop.name()) : prop.name().text);
				vs.push(prop.kind == KindPropertyAssignment ? named(prop.initializer(), staticName(prop.name())) : expr(prop.name()));
			}
			// (distinct keys: the literal's shape, made once)
			var distinct = [for (k in ks) k => true];
			if (Lambda.count(distinct) == ks.length && ks.length <= 64)
				return b.runtime("libLiteral", [reps.literalShape(ks), pack(vs)]);
			return b.runtime("libObject", [pack([for (k in ks) EStr(k)]), pack(vs)]);
		}
		var o = b.temp(b.runtime("libObject", [pack([]), pack([])]));
		var outer = env;
		env = env.copy();
		env.set("%home", {ty: TRef(RAny), cell: b.temp(ENewBox(TRef(RAny), o))});
		for (prop in props) switch (prop.kind) {
			case KindSpreadAssignment: b.runtime("libAssignSpread", [o, any(expr(prop.expression()))]);
			case KindShorthandPropertyAssignment: b.runtime("libDefineField", [o, EStr(prop.name().text), any(expr(prop.name()))]);
			case KindPropertyAssignment if (prop.name().kind != KindComputedPropertyName && prop.name().text == "__proto__"):
				b.runtime("libSetProto", [o, any(expr(prop.initializer()))]);
			case KindPropertyAssignment:
				var key = memberKey(prop.name());
				b.runtime("libDefineField", [o, any(key), any(named(prop.initializer(), staticName(prop.name())))]);
			case KindMethodDeclaration | KindGetAccessor | KindSetAccessor:
				var key = memberKey(prop.name());
				var fn = closure(prop, staticName(prop.name()));
				b.runtime("libDefineMethod", [o, any(key), fn, EInt(prop.kind == KindGetAccessor ? 1 : prop.kind == KindSetAccessor ? 2 : 0), bool(true)]);
			case _: fail(prop, "unsupported object member " + prop.kind.toString());
		}
		env = outer;
		return o;
	}

	// `a[k]` with a an array and k a number
	function arrayElement(n:Node):Bool
		return n.kind == KindElementAccessExpression && plainAccess(n) && types.isArray(n.expression().tsType) && types.isNumber(n.argumentExpression().tsType);

	// ---- number arrays (Reps: JsArray's nums)
	// `a[k]` of an array of numbers (number[], a branded number's, T extends number's)
	function numberElement(n:Node):Bool return arrayElement(n) && types.isNumber(n.expression().tsType.element);

	// an array literal of numbers, without holes or spreads (an empty one by
	// the type it is given: `const xs: number[] = []`)
	function numberLiteral(n:Node):Bool {
		var list = elements(n);
		for (e in list) if (e.kind == KindOmittedExpression || e.kind == KindSpreadElement) return false;
		function numbers(t:Null<TsType>) return types.isArray(t) && types.isNumber(t.element);
		if (numbers(n.tsType)) return true;
		if (list.length > 0 || n.parent == null) return false;
		var p = n.parent;
		return switch p.kind {
			case KindVariableDeclaration | KindPropertyDeclaration if (p.initializer() == n && p.name().kind == KindIdentifier): numbers(p.name().tsType);
			case KindBinaryExpression if (p.right() == n && p.operatorToken().kind == KindEqualsToken): numbers(p.left().tsType);
			case _: false;
		}
	}

	// n's value for a slot of type t: a number array's element read unboxed for a number's
	function valueFor(n:Node, t:Ty):Ex return t == TF64 ? numeric(n, true) : expr(n);

	// n's value where a number is wanted (slot: a typed slot's, its check
	// where it is none; else as ToNumber makes one): a number array's element
	// read unboxed, else the runtime's element made a number
	// (coerce: the operator makes a number of a value that is none, as
	// ToNumber does: not + nor a relation, whose operands' value it keeps)
	function numeric(n:Node, slot:Bool, coerce:Bool = true):Ex {
		var inner = strip(n);
		while (inner.kind == KindNonNullExpression) inner = strip(inner.expression());
		// (numbers' sum into a number's slot, of an object layout's reads: those
		// read into the slot too, a value that is no number stopping where it is
		// read rather than at the store; the other terms as + takes them)
		if (slot && inner.kind == KindBinaryExpression && inner.operatorToken().kind == KindPlusToken && types.isNumber(inner.left().tsType)
			&& types.isNumber(inner.right().tsType) && laidSum(inner)) {
			expressions++;
			function term(t:Node) return laidNumber(t) || laidSum(t) ? numeric(t, true) : numeric(t, false);
			var a = term(inner.left());
			return operate(KindPlusToken, a, term(inner.right()), inner);
		}
		if (inner.kind == KindPropertyAccessExpression && types.isNumber(inner.tsType) && (slot || coerce)) {
			var saved = numberRead, savedSlot = numberIntoSlot;
			numberRead = inner;
			numberIntoSlot = slot;
			var e = expr(n);
			numberRead = saved;
			numberIntoSlot = savedSlot;
			return e;
		}
		if (!numberElement(inner)) return expr(n);
		expressions++;
		typed++;
		typedOperations++;
		var obj = b.temp(expr(inner.expression()));
		var k = intOf(inner.argumentExpression()) ?? b.temp(number(expr(inner.argumentExpression())));
		return reps.arrayGetNumber(b, obj, k, g -> slot ? store(g, TF64) : number(g));
	}

	// (an operator that makes its operands numbers: arithmetic, the bitwise
	// ones, and a relation or + between numbers)
	function numericOperator(op:Kind, n:Node):Bool {
		if (op == KindMinusToken || op == KindAsteriskToken || op == KindSlashToken || op == KindPercentToken || op == KindAsteriskAsteriskToken) return true;
		if (op == KindAmpersandToken || op == KindBarToken || op == KindCaretToken || op == KindLessThanLessThanToken || op == KindGreaterThanGreaterThanToken
			|| op == KindGreaterThanGreaterThanGreaterThanToken) return true;
		var relation = op == KindLessThanToken || op == KindLessThanEqualsToken || op == KindGreaterThanToken || op == KindGreaterThanEqualsToken;
		return (relation || op == KindPlusToken) && n.kind == KindBinaryExpression && types.isNumber(n.left().tsType) && types.isNumber(n.right().tsType);
	}

	// a number array's element as a target whose value is read as a number (x[k] += 1, x[k]++)
	function numberTarget(n:Node):{read:() -> Ex, write:Ex->Void} {
		var obj = b.temp(expr(n.expression()));
		var key = intOf(n.argumentExpression()) ?? b.temp(number(expr(n.argumentExpression())));
		return {
			read: () -> reps.arrayGetNumber(b, obj, key, g -> number(g)),
			// (a value that is no number into the boxed path, which takes the key as a double: a counter's is an Int64)
			write: (e) -> Ir.typeOf(e) == TF64 ? reps.arraySetNumber(b, obj, key, e) : reps.arraySet(b, obj, Ir.typeOf(key) == TI64 ? EConv(L2F, key) : key, e)
		};
	}

	// (an assignment target that is a typed number slot: a binding or a typed class's field)
	function numberSlot(left:Node):Bool {
		return left.kind == KindIdentifier && env.exists(left.text) && env.get(left.text).ty == TF64 && env.get(left.text).buffer == null;
	}

	// A direct generic function's copy for numbers, where this call gives
	// each of its type parameters number (explicitly, or as an argument's type
	// for a parameter of type T or T[]): its typed slots of T numbers (Types.numberParams),
	// made once per function, at most COPIES of them, of functions of at most COPY_NODES nodes
	function specialization(name:String, n:Node, actual:Array<Node>):Null<FuncInfo> {
		var fn = nodes.get(name);
		var tps = fn == null ? null : fn.typeParameters();
		if (tps == null || tps.length == 0) return null;
		var ids = [];
		for (tp in tps) {
			var t = tp.name().tsType;
			if (t == null) return null;
			// (T extends number: a number already)
			if (!types.isNumber(t)) ids.push(t.id);
		}
		if (ids.length == 0) return null;
		var given = new Map<Int, Bool>();
		var explicit = n.typeArguments();
		if (explicit != null && explicit.length > 0) {
			for (i in 0...tps.length) if (i < explicit.length && ids.contains(tps[i].name().tsType.id)) given.set(tps[i].name().tsType.id, explicit[i].kind == KindNumberKeyword);
		}
		else {
			var params = parametersOf(fn);
			for (i in 0...params.length) {
				if (i >= actual.length || params[i].dotDotDotToken() != null || params[i].name().kind != KindIdentifier) break;
				var pt = params[i].name().tsType, at = actual[i].tsType;
				if (pt == null) continue;
				for (id in ids) {
					var number = pt.id == id ? types.isNumber(at) : pt.element != null && pt.element.id == id ? types.isArray(at) && types.isNumber(at.element) : null;
					if (number != null) given.set(id, (given.get(id) ?? true) && number);
				}
			}
		}
		for (id in ids) if (given.get(id) != true) return null;
		var m = moduleOf.get(fn.file.path);
		var key = fn.file.path + ":" + name;
		var f = specialized.get(key);
		if (f != null) return f;
		if (Lambda.count(specialized) >= COPIES || !copyable(fn)) return null;
		var saved = types.numberParams;
		types.numberParams = [for (id in ids) id => true];
		if (saved != null) for (id in saved.keys()) types.numberParams.set(id, true);
		f = declareFunction(fn, name + "_numbers", true);
		pendingCopies.push({m: m, n: fn, f: f, params: types.numberParams});
		types.numberParams = saved;
		specialized.set(key, f);
		return f;
	}

	// (a function small enough to copy, without a tagged template: its strings
	// array is one object per call site)
	static function copyable(fn:Node):Bool {
		var count = 0;
		function visit(x:Node):Bool {
			if (++count > COPY_NODES || x.kind == KindTaggedTemplateExpression) return false;
			for (c in x.children()) if (!visit(c)) return false;
			return true;
		}
		return visit(fn);
	}

	function construct(n:Node):Ex {
		var direct = layoutConstruct(n);
		if (direct != null) return direct;
		var callee = any(expr(n.expression()));
		return b.runtime("libConstruct", [callee, argumentList(n.arguments() == null ? [] : n.arguments()), callee]);
	}

	// Arguments to a known function: its parameters' types, missing ones
	// undefined, the rest (when it has a rest parameter) as an array.
	function positional(f:FuncInfo, values:Array<Ex>, skip:Int):Array<Ex> {
		var rest = restFunctions.exists(f);
		var fixed = f.args.length - skip - (rest ? 1 : 0);
		var out = [for (i in 0...fixed) store(i < values.length ? values[i] : b.runtime("getUndefined", []), f.args[i + skip].ty)];
		if (rest) out.push(b.runtime("libArray", [pack(values.slice(fixed))]));
		return out;
	}

	function hasSpread(nodes:Array<Node>):Bool {
		for (a in nodes) if (a.kind == KindSpreadElement) return true;
		return false;
	}

	// An argument (or array element) list as a runtime list, spreads expanded and holes kept.
	function spreadList(nodes:Array<Node>):Ex {
		var list = b.temp(ENewArr(TRef(RAny), new Vector(0)));
		for (e in nodes) switch (e.kind) {
			case KindSpreadElement: b.runtime("libAppendAll", [list, any(expr(e.expression()))]);
			case KindOmittedExpression: b.runtime("libAppend", [list, b.runtime("libHole", [])]);
			case _: b.runtime("libAppend", [list, any(expr(e))]);
		}
		return list;
	}

	function argumentList(nodes:Array<Node>):Ex return hasSpread(nodes) ? spreadList(nodes) : pack(actuals(nodes));

	// (in an optional chain, a nullish value at `?.` ends the whole chain with undefined)
	function chainCheck(n:Node, value:Ex) {
		if (n.questionDotToken() == null) return;
		if (b.depth != chainDepth) fail(n, "optional chain inside a nested loop");
		b.out.push(SIf(b.runtime("looseEq", [any(value), ENull(TRef(RAny))]), Vector.fromArrayCopy([SBreak]), new Vector(0)));
	}
	function chainTop(n:Node):Bool {
		if (n.flags & NodeFlags.OptionalChain == 0 || chainTops.exists(n)) return false;
		var parent = n.parent;
		return parent == null || parent.flags & NodeFlags.OptionalChain == 0 || parent.expression() != n
			|| !(parent.kind == KindPropertyAccessExpression || parent.kind == KindElementAccessExpression || parent.kind == KindCallExpression || parent.kind == KindNonNullExpression);
	}

	function optionalChain(n:Node):Ex {
		var l = b.local("chain", TRef(RAny));
		b.out.push(SSet(l, b.runtime("getUndefined", [])));
		var saved = chainDepth;
		chainTops.set(n, true);
		irLoop(() -> {
			chainDepth = b.depth;
			b.out.push(SSet(l, any(expr(n))));
			b.out.push(SBreak);});
		chainTops.remove(n);
		chainDepth = saved;
		return ELocal(l);
	}

	// job(f) (helder/jobs, its check JobDefinition's): f's case among the
	// program's jobs (helder.jobs.script.Entry.call, written once the
	// program is lowered: Frontend), a function of its own run on the
	// worker (a browser worker's instance: the runtime started there, the
	// constants f reads set from those sent), and the value
	// helder.jobs.script.Job.make's, with the constants as they are now
	function job(n:Node, fn:Node, captures:Array<String>):Ex {
		var name = fn.name().text;
		if (bridge == null) fail(n, "job: helder/jobs is not declared to the program");
		if (fn.file != n.file) fail(n, 'job: $name is another module\'s (job(f) is written in f\'s module)');
		var f = functions.get(name);
		if (f == null) fail(n, 'job: $name is not a plain function (it uses this, is async or a generator)');
		var index = jobs.length;
		var fi = Builder.func(p, "job" + index + "_" + name, TRef(RAny));
		var cs = new Local(0, "captures", TRef(RAny)), input = new Local(1, "input", TRef(RAny));
		fi.args = [cs, input];
		var outer = b;
		b = new Builder(p, fi);
		var ready = b.runtime("libReady", []);
		var start = b.block(() -> {
			b.runtime("libInit", []);
			for (feature in Features.of(src)) b.runtime("libInstall" + feature, []);
			b.out.push(SExpr(ECall(reps.startup, new Vector(0))));
		});
		b.out.push(SIf(ready, Vector.fromArrayCopy([]), start));
		if (definitions.define("hxmc.target") == "wasm32-wasi")
			for (i in 0...captures.length) set(get(captures[i], fn), b.runtime("libGet", [ELocal(cs), b.coerce(EF64(i), TRef(RAny))]));
		var call = ECall(f, Vector.fromArrayCopy(positional(f, fn.parameters().length == 0 ? [] : [ELocal(input)], 0)));
		if (f.ret == TVoid) {
			b.out.push(SExpr(call));
			b.out.push(SReturn(b.runtime("getUndefined", [])));
		} else b.out.push(SReturn(any(b.temp(call))));
		b.finish();
		b = outer;
		jobs.push(fi);
		return bridge.call(bridge.fn("helder_jobs_script_Job_make"), [EInt(index), pack([for (c in captures) read(get(c, n))])]);
	}

	// image(path)... (helder/asset): the handle helder.asset.ScriptAssets
	// makes of its key's marker (TsAssets), and its file in a dev build
	function asset(n:Node, kind:String, path:String, file:Null<String>):Ex {
		if (bridge == null) fail(n, "Asset." + kind + ": helder/asset is not declared to the program");
		var args = [EStr(TsAssets.marker(path))];
		if (file != null) args.push(EStr(file));
		return bridge.call(bridge.fn("helder_asset_ScriptAssets_" + kind), args);
	}

	// `import x from "./x.png" with {type: "image"}`: x set to the asset's handle
	function assetImport(n:Node) {
		var a = TsAssets.imported(n);
		var clause = n.importClause();
		if (a == null || clause == null || clause.name() == null) return;
		var file = TsAssets.find(src, a.kind, a.path, n, definitions.define);
		set(get(clause.name().text, n), asset(n, a.kind, a.path, TsAssets.devFile(file, definitions.define)));
	}

	function call(n:Node):Ex {
		var actual = n.arguments();
		if (actual == null) actual = [];
		var callee = n.expression();
		if (callee.kind == KindSuperKeyword && superInit != null) return superInit(actual);
		// (a definition: compiled now, what its handler made its last argument; keep's slot)
		switch definitions.call(n) {
			case null:
			case Generated(json): return apply(any(expr(callee)), pack(actuals(actual).concat([EStr(json)])));
			case GeneratedWith(json, uniforms):
				return apply(any(expr(callee)), pack(actuals(actual).concat([EStr(json), b.runtime("libArray", [pack([for (u in uniforms) expr(u)])])])));
			case Keep(key, type, source, init):
				var f = any(expr(init));
				if (dev && bridge != null) return bridge.call(bridge.interop("hotKeep"), [f, EStr(key), EStr(type), EStr(source)]);
				return apply(f, pack([]));
			case Checked:
				var x = api == null ? null : apiCall(n);
				if (x == null) fail(n, "this definition is a call into helder's API (its module's declarations)");
				return x;
			case Dropped: return b.runtime("getUndefined", []);
			case Job(fn, captures): return job(n, fn, captures);
			case AssetCall(kind, path, file): return asset(n, kind, path, file);
			case Native(kind, def): return new Natives(cast this).library(n, kind, def);
			case Located(index, at):
				if (hasSpread(actual) || actual.length > index) return apply(expr(callee), argumentList(actual));
				var xs = actuals(actual);
				while (xs.length < index) xs.push(b.runtime("getUndefined", []));
				return apply(any(expr(callee)), pack(xs.concat([EStr(at)])));
		}
		if (callee.kind == KindSuperKeyword) {
			var list = argumentList(actual);
			var t = b.runtime("libSuperConstruct", [read(get("%class", n)), list, read(get("%newTarget", n))]);
			set(get("this", n), t);
			parameterProperties();
			return t;
		}
		if (callee.kind == KindPropertyAccessExpression && callee.expression().kind == KindIdentifier && callee.expression().text == "console" && !env.exists("console") && callee.name().text == "log") {
			// (numbers print through the typed path; other lines through Node's formatting)
			var values = hasSpread(actual) ? null : actuals(actual);
			if (values != null && values.length > 0 && values.filter(v -> Ir.typeOf(v) != TF64).length == 0) {
				for (i in 0...values.length) {
					if (i > 0) b.runtime("print", [EStr(" ")]);
					b.runtime("print", [b.runtime("consoleNumber", [values[i]])]);
				}
			}
			else b.runtime("print", [b.runtime("consoleLine", [values == null ? spreadList(actual) : pack(values)])]);
			b.runtime("print", [EStr("\n")]);
			return b.runtime("getUndefined", []);
		}
		if (callee.kind == KindIdentifier && !env.exists(callee.text) && functions.exists(callee.text) && n.questionDotToken() == null) {
			var f = specialization(callee.text, n, actual) ?? functions.get(callee.text);
			if (hasSpread(actual)) return apply(read(functionValues.get(callee.text)), spreadList(actual));
			typedOperations++;
			var fixed = f.args.length - (restFunctions.exists(f) ? 1 : 0);
			var args = positional(f, [for (i in 0...actual.length) valueFor(actual[i], i < fixed ? f.args[i].ty : TRef(RAny))], 0);
			if (f.ret == TVoid) {
				b.out.push(SExpr(ECall(f, Vector.fromArrayCopy(args))));
				return b.runtime("getUndefined", []);
			}
			return b.temp(ECall(f, Vector.fromArrayCopy(args)));
		}
		var math = mathCall(n, callee, actual);
		if (math != null) return math;
		// (s.charCodeAt(i) on a string: String.prototype's, read-only)
		if (callee.kind == KindPropertyAccessExpression && plainAccess(callee) && callee.name().text == "charCodeAt" && actual.length <= 1 && !hasSpread(actual)
			&& types.isString(callee.expression().tsType)) {
			var s = b.temp(expr(callee.expression()));
			var counter = actual.length == 0 ? null : intOf(actual[0]);
			if (counter != null && Ir.typeOf(s).match(TRef(RStr))) {
				// (a loop counter: at or past 2^31 past any string's end)
				typedOperations++;
				var c = b.local("code", TF64);
				b.out.push(SSet(c, EF64(Math.NaN)));
				b.out.push(SIf(EBin(LLt, counter, EBin(LShl, EConv(I2L, EInt(1)), EInt(31))), b.block(() -> b.out.push(SSet(c, b.runtime("stringCharCodeAtInt", [s, EConv(L2I, counter)])))), new Vector(0)));
				return ELocal(c);
			}
			var i = actual.length == 0 ? EF64(0) : b.temp(number(expr(actual[0])));
			if (Ir.typeOf(s).match(TRef(RStr))) {
				typedOperations++;
				return b.runtime("stringCharCodeAt", [s, i]);
			}
			return b.runtime("libCallMethod", [any(s), EStr("charCodeAt"), pack([i])]);
		}
		// (a.push(v) of a number on a number array: appended unboxed, while Array.prototype's push is the built-in)
		if (callee.kind == KindPropertyAccessExpression && plainAccess(callee) && callee.name().text == "push" && actual.length == 1 && !hasSpread(actual)
			&& n.questionDotToken() == null && types.isArray(callee.expression().tsType) && types.isNumber(callee.expression().tsType.element)) {
			var o = b.temp(expr(callee.expression()));
			var v = b.temp(expr(actual[0]));
			if (Ir.typeOf(v) == TF64) {
				typedOperations++;
				var length = b.local("pushed", TF64), r = b.local("push", TRef(RAny));
				b.out.push(SSet(length, EF64(-1)));
				var fast = () -> b.out.push(SSet(length, b.runtime("libPushNumber", [ECast(TRef(RObj(reps.arrayClass)), o), v])));
				if (reps.exact(o, reps.arrayClass)) fast(); else b.out.push(SIf(EInstOf(reps.arrayClass, any(o)), b.block(fast), new Vector(0)));
				var used = n.parent == null || n.parent.kind != KindExpressionStatement;
				b.out.push(SIf(EBin(FLt, ELocal(length), EF64(0)), b.block(() -> b.out.push(SSet(r, b.runtime("libCallMethod", [any(o), EStr("push"), pack([v])])))),
					b.block(() -> if (used) b.out.push(SSet(r, any(ELocal(length)))))));
				if (!used) return b.runtime("getUndefined", []);
				return ELocal(r);
			}
			return b.runtime("libCallMethod", [any(o), EStr("push"), pack([v])]);
		}
		var inner = callee;
		while (inner.kind == KindParenthesizedExpression) inner = inner.expression();
		var method = layoutCall(n, inner, actual);
		if (method != null) return method;
		if ((inner.kind == KindPropertyAccessExpression || inner.kind == KindElementAccessExpression) && inner.expression().kind == KindSuperKeyword) {
			var key = inner.kind == KindPropertyAccessExpression ? EStr(inner.name().text) : any(expr(inner.argumentExpression()));
			return b.runtime("libSuperCall", [read(get("%home", n)), thisValue(), key, argumentList(actual)]);
		}
		if (inner.kind == KindPropertyAccessExpression || inner.kind == KindElementAccessExpression) {
			var obj = b.temp(any(expr(inner.expression())));
			chainCheck(inner, obj);
			var key:Ex = inner.kind == KindElementAccessExpression ? b.temp(any(expr(inner.argumentExpression()))) : inner.name().kind == KindPrivateIdentifier ? null : EStr(inner.name().text);
			var named = inner.kind == KindPropertyAccessExpression && key != null;
			if (key == null || n.questionDotToken() != null) {
				var fn = key == null ? b.runtime("libPrivateGet", [obj, EStr(brand(inner.name()))]) : named ? reps.siteGet(b, obj, inner.name().text) : b.runtime("libGet", [obj, key]);
				chainCheck(n, fn);
				return b.runtime("libCall", [fn, obj, argumentList(actual)]);
			}
			if (named) return reps.siteCall(b, obj, inner.name().text, argumentList(actual));
			return b.runtime("libCallMethod", [obj, key, argumentList(actual)]);
		}
		var fn = expr(callee);
		chainCheck(n, fn);
		return apply(fn, argumentList(actual));
	}
}
