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
import helder.typescript.lower.Api;
import helder.typescript.lower.Core;
import helder.typescript.lower.Core.*;

// Classes: a class's value (its constructor and prototype), those with a
// layout (typed slots, direct methods) and their calls.
@:access(helder.typescript.lower.Core)
abstract class ClassValues extends Expressions {
	// Classes. The constructor and the instance field initializer are closures
	// created before the class object; members are defined on the prototype or
	// the class in order, then static fields and blocks run with `this` as the
	// class. Private names get a brand per class evaluation site.
	function classValue(n:Node, ?name:String):Ex {
		var layout = classes.declared(n);
		if (layout != null) return layoutClassValue(n, layout);
		var own = n.name() != null ? n.name().text : name == null ? "" : name;
		var heritage:Node = null;
		var clauses = n.heritageClauses();
		if (clauses != null) for (h in clauses) if (h.token() == KindExtendsKeyword) heritage = h.types()[0].expression();
		var parent = heritage == null ? b.runtime("libHole", []) : any(expr(heritage));
		var outer = env;
		env = env.copy();
		var classCell = b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])));
		var classBinding = {ty: TRef(RAny), cell: classCell};
		var protoCell = b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])));
		var protoBinding = {ty: TRef(RAny), cell: protoCell};
		if (n.name() != null) env.set(own, classBinding);
		env.set("%class", classBinding);
		var serialNumber = classSerial++;
		var scope:Map<String, String> = [];
		for (m in members(n)) if (m.name() != null && m.name().kind == KindPrivateIdentifier) scope.set(m.name().text, "\x00" + m.name().text + "@" + serialNumber);
		privateScopes.push(scope);
		var instanceFields = [for (m in members(n)) if (m.kind == KindPropertyDeclaration && !hasModifier(m, KindStaticKeyword) && !hasModifier(m, KindDeclareKeyword) && !hasModifier(m, KindAbstractKeyword)) m];
		var privateMethods = [for (m in members(n)) if ((m.kind == KindMethodDeclaration || m.kind == KindGetAccessor || m.kind == KindSetAccessor) && m.name().kind == KindPrivateIdentifier && m.body() != null) m];
		// (cells for computed field keys and private methods, filled in member order)
		// (named in the environment, so the field initializer captures them)
		var keyCells:Map<Node, String> = [];
		for (m in instanceFields.concat(privateMethods)) if (m.name().kind == KindComputedPropertyName || privateMethods.indexOf(m) >= 0 && !hasModifier(m, KindStaticKeyword)) {
			var cellName = "%member" + (serial++);
			keyCells.set(m, cellName);
			env.set(cellName, {ty: TRef(RAny), cell: b.temp(ENewBox(TRef(RAny), b.runtime("getUndefined", [])))});
		}
		var ctorNode:Node = null;
		for (m in members(n)) if (m.kind == KindConstructor && m.body() != null) ctorNode = m;
		var derived = heritage != null;
		env.set("%home", protoBinding);
		var ctor = lambda(ctorNode, ["%newTarget"], false, ctorNode == null && derived, f -> {
			// (an implicit constructor's frame at its class, as V8's)
			if (ctorNode == null) {
				f.display = "new " + own;
				if (lines) at(n);
			}
			b.constructorThis = env.get("this");
			var props:Array<String> = [];
			if (ctorNode != null) for (param in parametersOf(ctorNode)) if (param.name().kind == KindIdentifier && (hasModifier(param, KindPublicKeyword) || hasModifier(param, KindPrivateKeyword) || hasModifier(param, KindProtectedKeyword) || hasModifier(param, KindReadonlyKeyword) || hasModifier(param, KindOverrideKeyword))) props.push(param.name().text);
			b.parameterProperties = props;
			if (ctorNode != null) {
				hoist(ctorNode.body(), false);
				parameterSetup(ctorNode);
			}
			if (!derived) parameterProperties();
			if (ctorNode != null) statement(ctorNode.body());
			else if (derived) {
				var t = b.runtime("libSuperConstruct", [read(env.get("%class")), b.runtime("libList", [read(env.get("%arguments"))]), read(env.get("%newTarget"))]);
				set(env.get("this"), t);
			}
			b.out.push(SReturn(read(env.get("this"))));
		});
		var fields:Ex = ENull(TRef(RAny));
		if (instanceFields.length > 0 || privateMethods.filter(m -> !hasModifier(m, KindStaticKeyword)).length > 0) {
			fields = lambda(null, [], false, false, f -> {
				f.display = own + ".<instance_members_initializer>";
				var self = read(env.get("this"));
				for (m in privateMethods) if (!hasModifier(m, KindStaticKeyword))
					b.runtime("libPrivateDefine", [self, EStr(brand(m.name())), read(env.get(keyCells.get(m))), EInt(m.kind == KindGetAccessor ? 1 : m.kind == KindSetAccessor ? 2 : 3)]);
				for (m in instanceFields) {
					var value = m.initializer() == null ? b.runtime("getUndefined", []) : named(m.initializer(), staticName(m.name()));
					if (m.name().kind == KindPrivateIdentifier) b.runtime("libPrivateDefine", [self, EStr(brand(m.name())), any(value), EInt(0)]);
					else b.runtime("libDefineField", [self, keyCells.exists(m) ? read(env.get(keyCells.get(m))) : memberKey(m.name()), any(value)]);
				}
				b.out.push(SReturn(b.runtime("getUndefined", [])));
			}).clos;
		}
		var c = b.temp(b.runtime("libClass", [EStr(own), parent, ctor.clos, EInt(ctor.arity), bool(ctor.rest), fields]));
		set(classBinding, c);
		set(protoBinding, b.runtime("libGet", [c, EStr("prototype")]));
		var statics:Array<Node> = [];
		for (m in members(n)) {
			var isStatic = hasModifier(m, KindStaticKeyword);
			switch (m.kind) {
				case KindMethodDeclaration | KindGetAccessor | KindSetAccessor if (m.body() != null):
					env.set("%home", isStatic ? classBinding : protoBinding);
					var kind = m.kind == KindGetAccessor ? 1 : m.kind == KindSetAccessor ? 2 : 0;
					var fnName = m.name().kind == KindPrivateIdentifier ? m.name().text : staticName(m.name());
					if (m.name().kind == KindPrivateIdentifier) {
						var fn = closure(m, fnName);
						if (isStatic) b.runtime("libPrivateDefine", [c, EStr(brand(m.name())), fn, EInt(kind == 0 ? 3 : kind)]);
						else set(env.get(keyCells.get(m)), fn);
					}
					else {
						var key = memberKey(m.name());
						var fn = closure(m, fnName);
						b.runtime("libDefineMethod", [isStatic ? c : read(protoBinding), any(key), fn, EInt(kind), bool(false)]);
					}
				case KindPropertyDeclaration if (isStatic): statics.push(m);
				case KindPropertyDeclaration: if (keyCells.exists(m)) set(env.get(keyCells.get(m)), memberKey(m.name()));
				case KindClassStaticBlockDeclaration: statics.push(m);
				case KindConstructor | KindMethodDeclaration | KindGetAccessor | KindSetAccessor | KindSemicolonClassElement | KindIndexSignature:
				case _: fail(m, "unsupported class member " + m.kind.toString());
			}
		}
		staticMembers(statics, classBinding, c, own);
		privateScopes.pop();
		env = outer;
		return c;
	}

	// a class's init (its constructor on a made instance) and direct methods,
	// declared before any code: call sites anywhere call them
	function declareLayout(c:ClassLayout) {
		c.prototype = anonymousGlobal("prototype_" + c.name).global;
		c.layout = anonymousGlobal("layout_" + c.name).global;
		function withThis(f:FuncInfo):FuncInfo {
			for (a in f.args) a.id++;
			f.args.unshift(new Local(0, "this", TRef(RObj(c.info))));
			return f;
		}
		var ctor = c.constructor();
		if (ctor != null) c.init = declareFunction(ctor, "init_" + c.name, true);
		else if (c.parent != null) {
			// (an implicit derived constructor passes its arguments on: the parent's init's)
			c.init = Builder.func(p, "init_" + c.name, TVoid);
			for (a in c.parent.init.args.slice(1)) c.init.args.push(new Local(c.init.args.length, a.name, a.ty));
			if (restFunctions.exists(c.parent.init)) restFunctions.set(c.init, true);
		}
		else c.init = Builder.func(p, "init_" + c.name, TVoid);
		if (ctor == null) c.init.display = "new " + c.name;
		c.init.ret = TVoid;
		withThis(c.init);
		for (m in c.node.members()) if (Classes.direct(m)) {
			var f = declareFunction(m, c.name + "_" + m.name().text, true);
			f.ret = reps.rep(m.returnType());
			c.methods.set(m.name().text, withThis(f));
		}
		for (m in c.node.members()) if (Classes.directAccessor(m)) {
			var get = m.kind == KindGetAccessor;
			var f = declareFunction(m, c.name + (get ? "_get_" : "_set_") + m.name().text, true);
			f.ret = get ? reps.rep(m.returnType()) : TVoid;
			(get ? c.getters : c.setters).set(m.name().text, withThis(f));
		}
	}

	function layoutClassValue(n:Node, c:ClassLayout):Ex {
		var own = n.name().text;
		var heritage:Node = null;
		for (h in n.heritageClauses() ?? []) if (h.token() == KindExtendsKeyword) heritage = h.types()[0].expression();
		var parent = heritage == null ? b.runtime("libHole", []) : any(expr(heritage));
		var outer = env;
		env = env.copy();
		// (the class's own scope in globals: its direct functions and closures reach them)
		var classBinding = anonymousGlobal("class_" + own);
		var protoBinding = {ty: TRef(RAny), global: c.prototype};
		env.set(own, classBinding);
		env.set("%class", classBinding);
		var serialNumber = classSerial++;
		var scope:Map<String, String> = [];
		for (m in members(n)) if (m.name() != null && m.name().kind == KindPrivateIdentifier) scope.set(m.name().text, "\x00" + m.name().text + "@" + serialNumber);
		privateScopes.push(scope);
		var instanceFields = [for (m in members(n)) if (m.kind == KindPropertyDeclaration && !hasModifier(m, KindStaticKeyword) && !hasModifier(m, KindDeclareKeyword) && !hasModifier(m, KindAbstractKeyword)) m];
		var privateMethods = [for (m in members(n)) if ((m.kind == KindMethodDeclaration || m.kind == KindGetAccessor || m.kind == KindSetAccessor) && m.name().kind == KindPrivateIdentifier && m.body() != null) m];
		var keys:Map<Node, String> = [];
		for (m in instanceFields.concat(privateMethods)) if (m.name().kind == KindComputedPropertyName || privateMethods.indexOf(m) >= 0 && !hasModifier(m, KindStaticKeyword)) {
			var name = "%member" + (serial++);
			keys.set(m, name);
			env.set(name, anonymousGlobal("member"));
		}
		var ctor = c.constructor();
		var props = ctor == null ? [] : [for (param in parametersOf(ctor)) if (param.name().kind == KindIdentifier && Classes.isParameterProperty(param)) param.name().text];
		env.set("%home", protoBinding);
		// (the init: field initializers, parameter properties, the constructor's body)
		compileDirect(c.init, ctor ?? n, arrowsUseThis(instanceFields.concat(ctor == null ? [] : [ctor.body()])), () -> {
			// (an implicit constructor's frame at its class, as V8's)
			if (lines && ctor == null) at(n);
			var self = read(env.get("this"));
			function fields() {
				for (m in privateMethods) if (!hasModifier(m, KindStaticKeyword))
					b.runtime("libPrivateDefine", [any(self), EStr(brand(m.name())), read(env.get(keys.get(m))), EInt(m.kind == KindGetAccessor ? 1 : m.kind == KindSetAccessor ? 2 : 3)]);
				for (m in instanceFields) {
					if (m.initializer() == null && m.name().kind != KindPrivateIdentifier && !keys.exists(m)) continue;
					var value = m.initializer() == null ? b.runtime("getUndefined", []) : named(m.initializer(), staticName(m.name()));
					if (m.name().kind == KindPrivateIdentifier) b.runtime("libPrivateDefine", [any(self), EStr(brand(m.name())), any(value), EInt(0)]);
					else if (keys.exists(m)) b.runtime("libDefineField", [any(self), read(env.get(keys.get(m))), any(value)]);
					else reps.fieldSet(b, c, self, m.name().text, value, where());
				}
				for (name in props) reps.fieldSet(b, c, self, name, read(get(name, ctor)), where());
			}
			var savedSuper = superInit;
			superInit = c.parent == null ? null : actual -> {
				if (hasSpread(actual)) fail(actual[0], "a spread in super() of a class with a typed layout");
				b.out.push(SExpr(ECall(c.parent.init, Vector.fromArrayCopy([ECast(TRef(RObj(c.parent.info)), self)].concat(positional(c.parent.init, actuals(actual), 1))))));
				fields();
				return any(self);
			};
			if (ctor != null) {
				hoist(ctor.body(), false);
				parameterSetup(ctor);
			}
			if (c.parent == null) fields();
			if (ctor != null) statement(ctor.body());
			else if (c.parent != null) {
				b.out.push(SExpr(ECall(c.parent.init, Vector.fromArrayCopy([ECast(TRef(RObj(c.parent.info)), self)].concat([for (a in c.init.args.slice(1)) ELocal(a)])))));
				fields();
			}
			superInit = savedSuper;
		});
		// (constructed dynamically: Lib.construct makes a base class's instance; a derived one makes its own)
		var construct = directValue(c.init, ["%newTarget"], args -> {
			var made = heritage == null ? ELocal(args[0]) : b.runtime("libAllocate", [ELocal(args[1])]);
			var o = b.temp(store(made, TRef(RObj(c.info))));
			b.out.push(SExpr(ECall(c.init, Vector.fromArrayCopy([o].concat([for (i in 1...c.init.args.length) store(ELocal(args[1 + i]), c.init.args[i].ty)])))));
			return o;
		});
		var cls = b.temp(b.runtime("libClass", [EStr(own), parent, construct.clos, EInt(construct.arity), bool(construct.rest), ENull(TRef(RAny))]));
		reps.linkClass(b, c, cls);
		set(classBinding, cls);
		set(protoBinding, b.runtime("libGet", [cls, EStr("prototype")]));
		b.out.push(SSetGlobal(c.layout, b.runtime("libLayoutOf", [cls])));
		var statics:Array<Node> = [];
		for (m in members(n)) {
			var isStatic = hasModifier(m, KindStaticKeyword);
			switch (m.kind) {
				case KindMethodDeclaration if (Classes.direct(m)):
					var f = c.methods.get(m.name().text);
					compileDirect(f, m, arrowsUseThis([m.body()]), () -> {
						hoist(m.body(), false);
						parameterSetup(m);
						statement(m.body());
					});
					var value = directValue(f, [], args -> {
						var call = ECall(f, Vector.fromArrayCopy([for (i in 0...f.args.length) store(ELocal(args[i]), f.args[i].ty)]));
						if (f.ret == TVoid) {
							b.out.push(SExpr(call));
							return b.runtime("getUndefined", []);
						}
						return b.temp(call);
					});
					b.runtime("libDefineMethod", [read(protoBinding), EStr(m.name().text), b.runtime("libFunction", [value.clos, EInt(value.arity), bool(value.rest), EInt(METHOD), EStr(m.name().text)]), EInt(0), bool(false)]);
				case KindGetAccessor | KindSetAccessor if (Classes.directAccessor(m)):
					var get = m.kind == KindGetAccessor;
					var f = (get ? c.getters : c.setters).get(m.name().text);
					compileDirect(f, m, arrowsUseThis([m.body()]), () -> {
						hoist(m.body(), false);
						parameterSetup(m);
						statement(m.body());
					});
					var value = directValue(f, [], args -> {
						var call = ECall(f, Vector.fromArrayCopy([for (i in 0...f.args.length) store(ELocal(args[i]), f.args[i].ty)]));
						if (f.ret == TVoid) {
							b.out.push(SExpr(call));
							return b.runtime("getUndefined", []);
						}
						return b.temp(call);
					});
					b.runtime("libDefineMethod", [read(protoBinding), EStr(m.name().text), b.runtime("libFunction", [value.clos, EInt(value.arity), bool(value.rest), EInt(METHOD), EStr(m.name().text)]), EInt(get ? 1 : 2), bool(false)]);
				case KindMethodDeclaration | KindGetAccessor | KindSetAccessor if (m.body() != null):
					env.set("%home", isStatic ? classBinding : protoBinding);
					var kind = m.kind == KindGetAccessor ? 1 : m.kind == KindSetAccessor ? 2 : 0;
					var fnName = m.name().kind == KindPrivateIdentifier ? m.name().text : staticName(m.name());
					var fn = closure(m, fnName);
					if (m.name().kind == KindPrivateIdentifier) {
						if (isStatic) b.runtime("libPrivateDefine", [cls, EStr(brand(m.name())), fn, EInt(kind == 0 ? 3 : kind)]);
						else set(env.get(keys.get(m)), fn);
					}
					else b.runtime("libDefineMethod", [isStatic ? cls : read(protoBinding), any(memberKey(m.name())), fn, EInt(kind), bool(false)]);
					env.set("%home", protoBinding);
				case KindPropertyDeclaration if (isStatic): statics.push(m);
				case KindPropertyDeclaration: if (keys.exists(m)) set(env.get(keys.get(m)), memberKey(m.name()));
				case KindClassStaticBlockDeclaration: statics.push(m);
				case KindConstructor | KindMethodDeclaration | KindGetAccessor | KindSetAccessor | KindSemicolonClassElement | KindIndexSignature:
				case _: fail(m, "unsupported class member " + m.kind.toString());
			}
		}
		staticMembers(statics, classBinding, cls, own);
		// (its methods are called directly: the prototype stays as defined)
		b.runtime("libLock", [read(protoBinding)]);
		privateScopes.pop();
		env = outer;
		return cls;
	}

	// (static fields and blocks, in order: `this` is the class)
	function staticMembers(statics:Array<Node>, classBinding:Binding, c:Ex, own:String) {
		env.set("%home", classBinding);
		for (m in statics) {
			var saved = env.get("this");
			env.set("this", classBinding);
			if (m.kind == KindClassStaticBlockDeclaration) {
				var body = m.body();
				var block = lambda(null, [], false, false, f -> {
					f.display = own + ".<static_initializer>";
					hoist(body, false);
					statement(body);
					b.out.push(SReturn(b.runtime("getUndefined", [])));});
				b.runtime("libCall", [b.runtime("libFunction", [block.clos, EInt(0), bool(false), EInt(METHOD), EStr("")]), c, pack([])]);
			}
			else {
				var key = m.name().kind == KindPrivateIdentifier ? null : memberKey(m.name());
				var value = m.initializer() == null ? b.runtime("getUndefined", []) : named(m.initializer(), staticName(m.name()));
				if (key == null) b.runtime("libPrivateDefine", [c, EStr(brand(m.name())), any(value), EInt(0)]);
				else b.runtime("libDefineField", [c, any(key), any(value)]);
			}
			if (saved == null) env.remove("this"); else env.set("this", saved);
		}
	}

	// `new C(...)` of a class with a layout, C its declaration's name or an
	// import of it (helder/math's Vec3 in a program's module): made and
	// initialized directly (before its declaration ran: the runtime's way,
	// which throws)
	function layoutConstruct(n:Node):Null<Ex> {
		var callee = n.expression(), actual = n.arguments() ?? [];
		if (callee.kind != KindIdentifier || hasSpread(actual)) return null;
		var c = classes.of(callee.symbol);
		if (c != null && c.node.name().symbol != callee.symbol) return null;
		if (c == null) c = importedClass(callee);
		if (c == null) return null;
		var args = actuals(actual);
		var l = b.local("made", TRef(RObj(c.info)));
		var fast = b.block(() -> {
			var o = reps.allocate(b, c, EGlobal(c.prototype, TRef(RAny)));
			b.out.push(SExpr(ECall(c.init, Vector.fromArrayCopy([o].concat(positional(c.init, args, 1))))));
			b.out.push(SSet(l, o));
		});
		var slow = b.block(() -> {
			var cls = b.temp(any(expr(callee)));
			b.out.push(SSet(l, store(b.runtime("libConstruct", [cls, pack(args), cls]), TRef(RObj(c.info)))));
		});
		b.out.push(SIf(EBin(RefEq, EGlobal(c.prototype, TRef(RAny)), ENull(TRef(RAny))), slow, fast));
		typedOperations++;
		return ELocal(l);
	}

	// `x instanceof C` of a class with a layout, C its declaration's name or
	// an import of it: true where x is an instance of its hxmc class (its
	// prototype C's or a subclass's: no prototype is set), else the
	// runtime's way (an instance of none of them, a class's own
	// Symbol.hasInstance)
	function layoutInstanceOf(x:Ex, rhs:Node):Null<Ex> {
		if (rhs.kind != KindIdentifier) return null;
		var c = classes.of(rhs.symbol);
		if (c != null && c.node.name().symbol != rhs.symbol) return null;
		if (c == null) c = importedClass(rhs);
		if (c == null || Lambda.exists(c.node.members(), m -> hasModifier(m, KindStaticKeyword) && m.name() != null && m.name().kind == KindComputedPropertyName)) return null;
		var v = b.temp(any(x));
		var l = b.local("instance", TBool);
		b.out.push(SIf(EInstOf(c.info, v), Vector.fromArrayCopy([SSet(l, bool(true))]),
			b.block(() -> b.out.push(SSet(l, b.runtime("libInstanceOf", [v, any(expr(rhs))]))))));
		typedOperations++;
		return ELocal(l);
	}

	// (`super` in an instance method or accessor of a class with a layout,
	// directly or in its arrows, `this` typed: the parent, whose prototype
	// is locked, so its member is the one super finds)
	function superLayout(n:Node):Null<ClassLayout> {
		var f = n.parent;
		while (f != null && f.kind != KindMethodDeclaration && f.kind != KindGetAccessor && f.kind != KindSetAccessor && f.kind != KindConstructor
			&& f.kind != KindFunctionDeclaration && f.kind != KindFunctionExpression && f.kind != KindClassDeclaration && f.kind != KindClassExpression
			&& f.kind != KindPropertyDeclaration && f.kind != KindClassStaticBlockDeclaration)
			f = f.parent;
		if (f == null || f.kind == KindFunctionDeclaration || f.kind == KindFunctionExpression || f.kind == KindClassDeclaration || f.kind == KindClassExpression
			|| f.kind == KindPropertyDeclaration || f.kind == KindClassStaticBlockDeclaration || hasModifier(f, KindStaticKeyword) || f.parent == null)
			return null;
		var c = classes.declared(f.parent);
		var self = env.get("this");
		if (c == null || c.parent == null || self == null || !self.ty.match(TRef(RObj(_)))) return null;
		return c.parent;
	}

	// super.m(...) and super.x of a parent with a layout: its direct function
	function layoutSuperCall(n:Node, inner:Node, actual:Array<Node>):Null<Ex> {
		if (inner.kind != KindPropertyAccessExpression || hasSpread(actual)) return null;
		var p = superLayout(inner), f = p?.method(inner.name().text);
		if (f == null) return null;
		var self = read(env.get("this"));
		var e = ECall(f, Vector.fromArrayCopy([ECast(f.args[0].ty, self)].concat(positional(f, actuals(actual), 1))));
		typedOperations++;
		if (f.ret != TVoid) return b.temp(e);
		b.out.push(SExpr(e));
		return b.runtime("getUndefined", []);
	}

	function layoutSuperGet(n:Node):Null<Ex> {
		var p = superLayout(n), f = p?.getter(n.name().text);
		if (f == null) return null;
		typedOperations++;
		return b.temp(ECall(f, Vector.fromArrayCopy([ECast(f.args[0].ty, read(env.get("this")))])));
	}

	// the class with a layout an identifier is an import of (`import {C}
	// from "./c"`, or `{D as C}`: the module's exported class declaration of
	// that name), else null (another binding of the name, a re-export)
	function importedClass(id:Node):Null<ClassLayout> {
		for (s in id.file.root.statements()) {
			if (s.kind != KindImportDeclaration || s.importClause() == null || s.importClause().isTypeOnly()) continue;
			var bindings = s.importClause().namedBindings();
			if (bindings == null || bindings.kind != KindNamedImports) continue;
			for (e in bindings.elements()) {
				if (e.name().symbol != id.symbol || e.isTypeOnly()) continue;
				var name = e.propertyName() != null ? e.propertyName().text : e.name().text;
				var target = src.resolve(s.moduleSpecifier());
				if (target == null) return null;
				for (c in classes.all)
					if (c.node.file.path == target && c.node.name().text == name && Lambda.exists(c.node.modifiers(), m -> m.kind == KindExportKeyword)
						&& !Lambda.exists(c.node.modifiers(), m -> m.kind == KindDefaultKeyword))
						return c;
				return null;
			}
		}
		return null;
	}

	// `o.m(...)` with o of a class with a layout: the method its class runs,
	// called directly (by o's prototype: the class or one of its subclasses
	// with layouts); else the runtime's way
	function layoutCall(n:Node, inner:Node, actual:Array<Node>):Null<Ex> {
		if (inner.kind != KindPropertyAccessExpression || !plainAccess(inner) || inner.name().kind == KindPrivateIdentifier || n.flags & NodeFlags.OptionalChain != 0 || hasSpread(actual)) return null;
		var c = reps.layoutOf(inner.expression().tsType), name = inner.name().text;
		if (c == null) return null;
		var cases = [for (x in classes.descendants(c)) if (x.method(name) != null) x];
		if (cases.length == 0) return null;
		var rets = [for (x in cases) x.method(name).ret];
		var ret = Lambda.foreach(rets, t -> Type.enumEq(t, rets[0])) && rets[0] != TVoid ? rets[0] : TRef(RAny);
		var o = b.temp(expr(inner.expression()));
		var args = [for (e in actuals(actual)) b.temp(e)];
		var l = b.local("result", ret);
		dispatch(o, c, x -> x.method(name), f -> positional(f, args, 1), l,
			() -> b.out.push(SSet(l, store(b.runtime("libCallMethod", [any(o), EStr(name), pack(args)]), ret))));
		typedOperations++;
		return ELocal(l);
	}

	// o's direct function found by its prototype (its class's or a subclass's
	// with a layout), called with args, its result into l; else slow
	function dispatch(o:Ex, c:ClassLayout, find:ClassLayout->Null<FuncInfo>, args:FuncInfo->Array<Ex>, l:Null<Local>, slow:() -> Void) {
		var cases = [for (x in classes.descendants(c)) if (find(x) != null) x];
		var fast = b.block(() -> {
			var proto = b.temp(EField(reps.objectBase, reps.objectBase.fieldIndex("proto"), ECast(TRef(RObj(reps.objectBase)), o)));
			var chain = b.block(slow);
			var i = cases.length;
			while (i-- > 0) {
				var f = find(cases[i]);
				var call = b.block(() -> {
					var e = ECall(f, Vector.fromArrayCopy([ECast(f.args[0].ty, o)].concat(args(f))));
					if (l == null) b.out.push(SExpr(e));
					else if (f.ret == TVoid) {
						b.out.push(SExpr(e));
						b.out.push(SSet(l, store(b.runtime("getUndefined", []), l.ty)));
					}
					else b.out.push(SSet(l, store(b.temp(e), l.ty)));
				});
				chain = Vector.fromArrayCopy([SIf(EBin(RefEq, proto, EGlobal(cases[i].prototype, TRef(RAny))), call, chain)]);
			}
			for (s in chain) b.out.push(s);
		});
		if (reps.exact(o, c.info)) for (s in fast) b.out.push(s);
		else b.out.push(SIf(EInstOf(c.info, any(o)), fast, b.block(slow)));
	}

	// `o.name` of a getter, `o.name = v` of a setter, o of a class with a
	// layout: its direct function by o's prototype, else the runtime's way
	function layoutAccessor(n:Node, get:Bool):Null<ClassLayout> {
		if (n.kind != KindPropertyAccessExpression || n.name().kind == KindPrivateIdentifier || !plainAccess(n) || n.flags & NodeFlags.OptionalChain != 0) return null;
		var c = reps.layoutOf(n.expression().tsType), name = n.name().text;
		if (c == null || c.declares(name)) return null;
		for (x in classes.descendants(c)) if ((get ? x.getter(name) : x.setter(name)) != null) return c;
		return null;
	}

	function layoutGet(n:Node, c:ClassLayout, o:Ex):Ex {
		var name = n.name().text;
		// (typed where every class's instance runs a getter: a setter alone
		// reads undefined; an abstract class has none of its own)
		var all = classes.descendants(c).filter(x -> !hasModifier(x.node, KindAbstractKeyword));
		var rets = [for (x in all) if (x.getter(name) != null) x.getter(name).ret];
		var ret = rets.length == all.length && Lambda.foreach(rets, t -> Type.enumEq(t, rets[0])) && rets[0] != TVoid ? rets[0] : TRef(RAny);
		var l = b.local("got", ret);
		dispatch(o, c, x -> x.getter(name), _ -> [], l, () -> b.out.push(SSet(l, store(reps.siteGet(b, any(o), name), ret))));
		typedOperations++;
		return ELocal(l);
	}

	function layoutSet(n:Node, c:ClassLayout, o:Ex, v:Ex) {
		var name = n.name().text;
		var value = b.temp(v);
		dispatch(o, c, x -> x.setter(name), f -> [store(value, f.args[1].ty)], null, () -> reps.sitePut(b, any(o), name, value));
		typedOperations++;
	}

	// `obj.name` with obj an instance of a class with a layout that declares the field
	function layoutField(n:Node):Null<ClassLayout> {
		if (n.kind != KindPropertyAccessExpression || n.name().kind == KindPrivateIdentifier || !plainAccess(n)) return null;
		var c = reps.layoutOf(n.expression().tsType);
		return c != null && c.declares(n.name().text) ? c : null;
	}

	// (constructor parameter properties: assigned after the fields, and after super() in derived classes)
	function parameterProperties() {
		if (b.parameterProperties == null) return;
		for (name in b.parameterProperties) b.runtime("libPut", [read(env.get("this")), EStr(name), any(read(get(name, null)))]);
	}
}
