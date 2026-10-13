(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.YashVM = factory();
})(typeof self !== "undefined" ? self : this, function () {

  function num(v) { return typeof v === "number" ? v : (v == null ? 0 : Number(v) || 0); }
  function verdade(v) { return v != null && v !== false; }
  function ehVetor(v) { return !!v && v.__y === "vetor"; }
  function ehCor(v) { return !!v && v.__y === "cor"; }
  function ehHandle(v) { return !!v && v.__y === "handle"; }
  function ehFn(v) { return !!v && (v.tipo === "funcao" || v.tipo === "nativo"); }

  function Vetor(x, y, z) { this.__y = "vetor"; this.x = num(x); this.y = num(y); this.z = num(z || 0); }

  function iguais(a, b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (ehVetor(a) && ehVetor(b)) return a.x === b.x && a.y === b.y && a.z === b.z;
    if (ehCor(a) && ehCor(b)) return a.r === b.r && a.g === b.g && a.b === b.b;
    return a === b;
  }
  function soma(a, b) {
    if (ehVetor(a) || ehVetor(b)) {
      a = ehVetor(a) ? a : new Vetor(a, a, a); b = ehVetor(b) ? b : new Vetor(b, b, b);
      return new Vetor(a.x + b.x, a.y + b.y, a.z + b.z);
    }
    return num(a) + num(b);
  }
  function mult(a, b) {
    if (ehVetor(a) && typeof b === "number") return new Vetor(a.x * b, a.y * b, a.z * b);
    if (ehVetor(b) && typeof a === "number") return new Vetor(b.x * a, b.y * a, b.z * a);
    return num(a) * num(b);
  }
  function comparar(op, a, b) {
    var x = ehVetor(a) ? a.x : a, y = ehVetor(b) ? b.x : b;
    if (op === "<") return x < y;
    if (op === ">") return x > y;
    if (op === "<=") return x <= y;
    if (op === ">=") return x >= y;
    return false;
  }
  function toText(v) {
    if (v == null) return "nulo";
    if (v === true) return "verdadeiro";
    if (v === false) return "falso";
    if (typeof v === "number") return String(v);
    if (typeof v === "string") return v;
    if (ehVetor(v)) return "(" + v.x + ", " + v.y + ", " + v.z + ")";
    if (ehCor(v)) return "rgb(" + Math.round(v.r) + ", " + Math.round(v.g) + ", " + Math.round(v.b) + ")";
    if (v.tipo === "funcao") return "<funcao " + v.nome + ">";
    if (v.tipo === "nativo") return "<nativo " + v.nome + ">";
    if (ehHandle(v)) return "<" + v.forma + " '" + v.nome + "'>";
    if (Array.isArray(v)) return "[" + v.map(toText).join(", ") + "]";
    return String(v);
  }

  function nat(nome, fn) { return { tipo: "nativo", nome: nome, fn: fn }; }
  function aleatorio(a) {
    var lo, hi;
    if (a.length >= 2) { lo = num(a[0]); hi = num(a[1]); } else { lo = 0; hi = num(a[0]); }
    if (hi < lo) { var t = lo; lo = hi; hi = t; }
    return lo + Math.random() * (hi - lo);
  }
  var BUILTINS = {
    rgb: nat("rgb", function (a) { return { __y: "cor", r: num(a[0]), g: num(a[1]), b: num(a[2]) }; }),
    vetor: nat("vetor", function (a) { return new Vetor(a[0], a[1], a[2]); }),
    abs: nat("abs", function (a) { return Math.abs(num(a[0])); }),
    piso: nat("piso", function (a) { return Math.floor(num(a[0])); }),
    teto: nat("teto", function (a) { return Math.ceil(num(a[0])); }),
    arredondar: nat("arredondar", function (a) { return Math.round(num(a[0])); }),
    min: nat("min", function (a) { return Math.min.apply(Math, a.map(num)); }),
    max: nat("max", function (a) { return Math.max.apply(Math, a.map(num)); }),
    raiz: nat("raiz", function (a) { return Math.sqrt(num(a[0])); }),
    seno: nat("seno", function (a) { return Math.sin(num(a[0])); }),
    cosseno: nat("cosseno", function (a) { return Math.cos(num(a[0])); }),
    aleatorio: nat("aleatorio", aleatorio),
    contar: nat("contar", function (a) {
      var v = a[0];
      if (v == null) return 0;
      if (Array.isArray(v) || typeof v === "string") return v.length;
      if (ehHandle(v) && v.props) return Object.keys(v.props).length;
      return 0;
    }),
    texto: nat("texto", function (a) { return toText(a[0]); }),
    numero: nat("numero", function (a) { return num(a[0]); }),
    distancia: nat("distancia", function (a) {
      var p = a[0] || {}, q = a[1] || {};
      return Math.sqrt(Math.pow(num(p.x) - num(q.x), 2) + Math.pow(num(p.y) - num(q.y), 2));
    })
  };

  function Ambiente(pai) { this.vars = Object.create(null); this.pai = pai || null; }
  Ambiente.prototype.obter = function (nome) { var e = this; while (e) { if (nome in e.vars) return e.vars[nome]; e = e.pai; } return undefined; };
  Ambiente.prototype.definir = function (nome, val) { this.vars[nome] = val; return val; };
  Ambiente.prototype.atribuir = function (nome, val) {
    var e = this;
    while (e) { if (nome in e.vars) { e.vars[nome] = val; return val; } e = e.pai; }
    this.vars[nome] = val; return val;
  };

  function Runtime(host) {
    this.host = host || {};
    this.agora = 0;
    this._corr = [];
    this._timers = [];
    this._eventos = [];
    this.limiteIter = 1000000;
  }
  Runtime.prototype.agendar = function (intervalo, fnGeradora) { this._timers.push({ intervalo: intervalo, acc: 0, fn: fnGeradora }); };
  Runtime.prototype.aoEvento = function (evento, alvo, fn) { this._eventos.push({ evento: evento, alvo: alvo, fn: fn }); };
  Runtime.prototype.emitir = function (evento, alvo, dados) {
    for (var i = 0; i < this._eventos.length; i++) {
      var h = this._eventos[i];
      if (h.evento === evento && (h.alvo == null || h.alvo === alvo)) this.spawn(h.fn(dados));
    }
  };
  Runtime.prototype.spawn = function (gen) { var c = { gen: gen, wake: this.agora, done: false }; this._corr.push(c); this._rodar(c); return c; };
  Runtime.prototype._rodar = function (c) {
    if (c.done) return;
    var r;
    try { r = c.gen.next(); }
    catch (e) { c.done = true; if (!(e && e.__retorno)) throw e; return; }
    if (r.done) { c.done = true; return; }
    var y = r.value;
    c.wake = this.agora + (y && typeof y.espera === "number" ? y.espera : 0);
  };
  Runtime.prototype.passo = function (dt) {
    this.agora += dt;
    for (var t = 0; t < this._timers.length; t++) {
      var tm = this._timers[t];
      if (tm.intervalo <= 0) continue;
      tm.acc += dt;
      var guarda = 0;
      while (tm.acc >= tm.intervalo && guarda++ < 1000) { tm.acc -= tm.intervalo; this.spawn(tm.fn()); }
    }
    var prontas = [];
    for (var i = 0; i < this._corr.length; i++) { var c = this._corr[i]; if (!c.done && c.wake <= this.agora) prontas.push(c); }
    for (var j = 0; j < prontas.length; j++) { if (!prontas[j].done) this._rodar(prontas[j]); }
    this._corr = this._corr.filter(function (c) { return !c.done; });
  };
  Runtime.prototype.vivas = function () { return this._corr.filter(function (c) { return !c.done; }).length; };

  function attr(ctx, o, prop) {
    if (o == null) return null;
    if (ehVetor(o)) return o[prop];
    if (ehCor(o)) return o[prop];
    if (ehHandle(o) && ctx.host.obter) return ctx.host.obter(o, prop);
    if (typeof o === "object") return o[prop];
    return null;
  }
  function idx(ctx, o, k) {
    if (o == null) return null;
    if (Array.isArray(o)) return o[num(k) - 1];
    if (typeof o === "string") return o.charAt(num(k) - 1);
    if (ehHandle(o) && ctx.host.obter) return ctx.host.obter(o, k);
    if (typeof o === "object") return o[k];
    return null;
  }
  function definirProp(ctx, o, prop, v) {
    if (o == null) return;
    if (ehHandle(o) && ctx.host.definir) return ctx.host.definir(o, prop, v);
    if (typeof o === "object") o[prop] = v;
  }
  function definirIdx(ctx, o, k, v) {
    if (o == null) return;
    if (Array.isArray(o)) { o[num(k) - 1] = v; return; }
    if (typeof o === "object") o[k] = v;
  }

  function* av(ctx, e, env) {
    if (!e) return null;
    switch (e.tipo) {
      case "num": return e.v;
      case "str": return e.v;
      case "bool": return e.v;
      case "nulo": return null;
      case "ident": {
        var v = env.obter(e.nome);
        if (v === undefined && e.nome === "eu") v = null;
        return v === undefined ? null : v;
      }
      case "vetor": {
        var it = [];
        for (var i = 0; i < e.itens.length; i++) it.push(yield* av(ctx, e.itens[i], env));
        return new Vetor(it[0], it[1], it[2]);
      }
      case "lista": {
        var lt = [];
        for (var j = 0; j < e.itens.length; j++) lt.push(yield* av(ctx, e.itens[j], env));
        return lt;
      }
      case "mapa": {
        var m = {};
        for (var p = 0; p < e.pares.length; p++) m[e.pares[p][0]] = yield* av(ctx, e.pares[p][1], env);
        return m;
      }
      case "unario": {
        var u = yield* av(ctx, e.valor, env);
        if (e.op === "-") return -num(u);
        if (e.op === "+") return num(u);
        return !verdade(u);
      }
      case "binario": {
        if (e.op === "e" || e.op === "and") { var l1 = yield* av(ctx, e.esq, env); return verdade(l1) ? verdade(yield* av(ctx, e.dir, env)) : false; }
        if (e.op === "ou" || e.op === "or") { var l2 = yield* av(ctx, e.esq, env); return verdade(l2) ? true : verdade(yield* av(ctx, e.dir, env)); }
        var a = yield* av(ctx, e.esq, env), b = yield* av(ctx, e.dir, env);
        switch (e.op) {
          case "+": return soma(a, b);
          case "-": return num(a) - num(b);
          case "*": return mult(a, b);
          case "/": return num(b) === 0 ? 0 : num(a) / num(b);
          case "//": return num(b) === 0 ? 0 : Math.floor(num(a) / num(b));
          case "%": return num(b) === 0 ? 0 : num(a) % num(b);
          case "^": return Math.pow(num(a), num(b));
          case "..": return toText(a) + toText(b);
          case "=": case "==": return iguais(a, b);
          case "!=": case "~=": return !iguais(a, b);
          case "<": case ">": case "<=": case ">=": return comparar(e.op, a, b);
        }
        return null;
      }
      case "acesso": return attr(ctx, yield* av(ctx, e.obj, env), e.prop);
      case "indice": return idx(ctx, yield* av(ctx, e.obj, env), yield* av(ctx, e.idx, env));
      case "chamada": {
        var args = [];
        for (var c = 0; c < e.args.length; c++) args.push(yield* av(ctx, e.args[c], env));
        if (e.callee.tipo === "acesso") {
          var obj = yield* av(ctx, e.callee.obj, env);
          if (ehHandle(obj) && ctx.host.metodo) return ctx.host.metodo(obj, e.callee.prop, args);
          var f = attr(ctx, obj, e.callee.prop);
          return yield* invocar(ctx, f, obj, args, e.linha);
        }
        var fn = yield* av(ctx, e.callee, env);
        return yield* invocar(ctx, fn, null, args, e.linha);
      }
      case "metodo": {
        var o2 = yield* av(ctx, e.obj, env);
        var a2 = [];
        for (var d = 0; d < e.args.length; d++) a2.push(yield* av(ctx, e.args[d], env));
        if (ehHandle(o2) && ctx.host.metodo) return ctx.host.metodo(o2, e.metodo, a2);
        var mf = attr(ctx, o2, e.metodo);
        return yield* invocar(ctx, mf, o2, a2, e.linha);
      }
    }
    return null;
  }

  function* invocar(ctx, fn, thisObj, args, linha) {
    if (fn && fn.tipo === "nativo") return fn.fn(args);
    if (fn && fn.tipo === "funcao") return yield* chamarFuncao(ctx, fn, args);
    if (typeof fn === "function") return fn.apply(thisObj, args);
    throw { erro: "tentativa de chamar algo que não é função", linha: linha };
  }

  function* chamarFuncao(ctx, fn, args) {
    var env = new Ambiente(fn.env);
    for (var i = 0; i < fn.params.length; i++) env.definir(fn.params[i], i < args.length ? args[i] : null);
    try { yield* executarBloco(ctx, fn.corpo, env); }
    catch (e) { if (e && e.__retorno) return e.valor; throw e; }
    return null;
  }

  function* executarBloco(ctx, lista, env) {
    if (!lista) return;
    for (var i = 0; i < lista.length; i++) yield* executarStmt(ctx, lista[i], env);
  }

  function* executarStmt(ctx, s, env) {
    switch (s.tipo) {
      case "criar": {
        var handle = ctx.host.criar ? ctx.host.criar(s.forma, s.nome) : { __y: "handle", forma: s.forma, nome: s.nome, props: {} };
        env.definir(s.nome, handle);
        var filho = new Ambiente(env);
        filho.definir("eu", handle);
        for (var i = 0; i < s.corpo.length; i++) {
          var st = s.corpo[i];
          if (st.tipo === "atribuir" && st.alvo.tipo === "ident") definirProp(ctx, handle, st.alvo.nome, yield* av(ctx, st.valor, filho));
          else yield* executarStmt(ctx, st, filho);
        }
        return;
      }
      case "quando": {
        var base = env;
        var alvo = s.alvo;
        ctx.rt.aoEvento(s.evento, alvo, function (dados) {
          return (function* () { var fe = new Ambiente(base); fe.definir("evento", dados == null ? null : dados); yield* executarBloco(ctx, s.corpo, fe); })();
        });
        return;
      }
      case "se": {
        for (var r = 0; r < s.ramos.length; r++) {
          if (verdade(yield* av(ctx, s.ramos[r].cond, env))) { yield* executarBloco(ctx, s.ramos[r].corpo, new Ambiente(env)); return; }
        }
        if (s.senao) yield* executarBloco(ctx, s.senao, new Ambiente(env));
        return;
      }
      case "enquanto": {
        var n = 0;
        while (verdade(yield* av(ctx, s.cond, env))) {
          yield* executarBloco(ctx, s.corpo, new Ambiente(env));
          if (++n > ctx.rt.limiteIter) throw { erro: "loop infinito detectado em 'enquanto'", linha: s.linha };
        }
        return;
      }
      case "paracada": {
        var lista = yield* av(ctx, s.lista, env);
        if (Array.isArray(lista)) {
          for (var k = 0; k < lista.length; k++) { var fe2 = new Ambiente(env); fe2.definir(s.var, lista[k]); yield* executarBloco(ctx, s.corpo, fe2); }
        }
        return;
      }
      case "funcao": env.definir(s.nome, { tipo: "funcao", nome: s.nome, params: s.params, corpo: s.corpo, env: env }); return;
      case "retornar": throw { __retorno: true, valor: s.valor ? yield* av(ctx, s.valor, env) : null };
      case "esperar": yield { espera: num(yield* av(ctx, s.valor, env)) }; return;
      case "acada": {
        var itv = num(yield* av(ctx, s.intervalo, env));
        ctx.rt.agendar(itv, function () { return (function* () { yield* executarBloco(ctx, s.corpo, new Ambiente(env)); })(); });
        return;
      }
      case "incluir": {
        if (ctx.host.incluir) {
          var res = ctx.host.incluir(s.caminho);
          if (res && res.corpo) yield* executarBloco(ctx, res.corpo, env);
        }
        return;
      }
      case "atribuir": {
        var v = yield* av(ctx, s.valor, env);
        if (s.alvo.tipo === "ident") env.atribuir(s.alvo.nome, v);
        else if (s.alvo.tipo === "acesso") definirProp(ctx, yield* av(ctx, s.alvo.obj, env), s.alvo.prop, v);
        else if (s.alvo.tipo === "indice") definirIdx(ctx, yield* av(ctx, s.alvo.obj, env), yield* av(ctx, s.alvo.idx, env), v);
        return;
      }
      case "expr": yield* av(ctx, s.valor, env); return;
      case "comando": {
        var vals = [];
        for (var q = 0; q < s.args.length; q++) {
          var ar = s.args[q];
          vals.push(ar.tipo === "sep" ? { sep: ar.v } : yield* av(ctx, ar.v, env));
        }
        if (ctx.host.comando) ctx.host.comando(s.verbo, vals, { env: env, linha: s.linha });
        return;
      }
    }
  }

  function ambienteGlobal() {
    var env = new Ambiente(null);
    for (var k in BUILTINS) env.definir(k, BUILTINS[k]);
    env.definir("pi", Math.PI);
    return env;
  }

  function executar(programa, host, opts) {
    host = host || {};
    var rt = new Runtime(host);
    var env = ambienteGlobal();
    var ctx = { rt: rt, host: host };
    rt.spawn((function* () { yield* executarBloco(ctx, programa.corpo, env); })());
    return {
      rt: rt,
      ambiente: env,
      ctx: ctx,
      iniciar: function () { rt.emitir("iniciar", null, null); },
      emitir: function (evento, alvo, dados) { rt.emitir(evento, alvo, dados); },
      passo: function (dt) { rt.passo(dt == null ? 1 / 60 : dt); }
    };
  }

  return {
    Runtime: Runtime,
    Ambiente: Ambiente,
    Vetor: Vetor,
    executar: executar,
    ambienteGlobal: ambienteGlobal,
    BUILTINS: BUILTINS,
    toText: toText,
    verdade: verdade,
    iguais: iguais
  };
});
