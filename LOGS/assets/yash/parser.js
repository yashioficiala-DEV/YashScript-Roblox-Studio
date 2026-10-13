(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.YashParser = factory();
})(typeof self !== "undefined" ? self : this, function () {
  var EVENTOS = {
    iniciar: 1, carregar: 1, tocar: 1, encostar: 1, clicar: 1,
    mouse_em: 1, mouse_sair: 1, apertar_tecla: 1, soltar_tecla: 1,
    apertar: 1, soltar: 1, morrer: 1, nascer: 1, entrar: 1, sair: 1, quadro: 1
  };
  var SEPARADORES = {
    a: 1, para: 1, entre: 1, de: 1, em: 1, e: 1, ou: 1, com: 1, na: 1, no: 1,
    sobre: 1, ate: 1, por: 1, ao: 1, pela: 1, pelo: 1, velocidade: 1,
    duracao: 1, animacao: 1, estilo: 1, tipo: 1, aos: 1, das: 1, dos: 1
  };
  var PREC = {
    "ou": 1, "or": 1, "e": 2, "and": 2,
    "<": 3, ">": 3, "<=": 3, ">=": 3, "==": 3, "=": 3, "!=": 3, "~=": 3,
    "..": 4, "+": 5, "-": 5, "*": 6, "/": 6, "//": 6, "%": 6, "^": 7
  };
  var DIREITA = { "^": 1 };
  var TERMOS_SE = ["senao", "senaose", "fim"];

  function normalizar(toks) {
    var out = [], i = 0, n = toks.length;
    function pal(k) { return toks[i + k] && toks[i + k].t === "word" ? toks[i + k].v : null; }
    while (i < n) {
      var t = toks[i];
      if (t.t === "word") {
        var a = pal(0), b = pal(1), c = pal(2);
        if (a === "menor" && b === "que") { out.push({ t: "sym", v: "<", l: t.l }); i += 2; continue; }
        if (a === "maior" && b === "que") { out.push({ t: "sym", v: ">", l: t.l }); i += 2; continue; }
        if (a === "igual" && b === "a") { out.push({ t: "sym", v: "==", l: t.l }); i += 2; continue; }
        if (a === "diferente" && b === "de") { out.push({ t: "sym", v: "!=", l: t.l }); i += 2; continue; }
        if (a === "menor" && b === "ou" && c === "igual") { out.push({ t: "sym", v: "<=", l: t.l }); i += 3; continue; }
        if (a === "maior" && b === "ou" && c === "igual") { out.push({ t: "sym", v: ">=", l: t.l }); i += 3; continue; }
      }
      out.push(t); i++;
    }
    return out;
  }

  function Parser(toks) { this.toks = normalizar(toks); this.i = 0; }
  Parser.prototype.at = function () { return this.toks[this.i]; };
  Parser.prototype.peek = function (k) { return this.toks[this.i + (k || 0)]; };
  Parser.prototype.av = function () { return this.toks[this.i++]; };
  Parser.prototype.eh = function (t, v) { var x = this.at(); return !!x && x.t === t && (v === undefined || x.v === v); };
  Parser.prototype.ehPal = function (v) { return this.eh("word", v); };
  Parser.prototype.esperar = function (t, v) {
    var x = this.at();
    if (!x || x.t !== t || (v !== undefined && x.v !== v)) this.erro("esperava '" + (v || t) + "' mas veio '" + (x ? x.v : "fim do arquivo") + "'");
    this.i++; return x.v;
  };
  Parser.prototype.pularNovas = function () { while (this.eh("new")) this.i++; };
  Parser.prototype.fimLinha = function () { var x = this.at(); return !x || x.t === "new" || x.t === "eof"; };
  Parser.prototype.erro = function (m) { var x = this.at(); throw { erro: m, linha: x ? x.l : 0 }; };
  Parser.prototype.exigeLinha = function () { if (!this.fimLinha()) this.erro("texto inesperado após a instrução"); this.pularNovas(); };
  Parser.prototype.esperaNome = function () { var x = this.at(); if (x && (x.t === "str" || x.t === "word")) { this.i++; return x.v; } return this.erro("nome esperado (aspas ou identificador)"); };

  Parser.prototype.parse = function () { return { tipo: "programa", corpo: this.bloco(["eof"]) }; };

  Parser.prototype.bloco = function (terms) {
    var out = [];
    this.pularNovas();
    while (!this.eh("eof") && !(this.at().t === "word" && terms.indexOf(this.at().v) >= 0)) {
      var s = this.declaracao();
      if (s) out.push(s);
      this.pularNovas();
    }
    return out;
  };

  Parser.prototype.declaracao = function () {
    var x = this.at();
    if (x && x.t === "word") {
      switch (x.v) {
        case "criar": return this.parseCriar();
        case "quando": return this.parseQuando();
        case "se": return this.parseSe();
        case "enquanto": return this.parseEnquanto();
        case "para": if (this.peek(1) && this.peek(1).t === "word" && this.peek(1).v === "cada") return this.parsePara();
          break;
        case "funcao": return this.parseFuncao();
        case "retornar": return this.parseRetornar();
        case "mostrar": return this.parseMostrar();
        case "esperar": return this.parseEsperar();
        case "a": if (this.peek(1) && this.peek(1).t === "word" && this.peek(1).v === "cada") return this.parseACada();
          break;
        case "incluir": return this.parseIncluir();
        case "fim": this.erro("'fim' sem bloco correspondente"); return null;
      }
    }
    return this.parseGenerico();
  };

  Parser.prototype.parseCriar = function () {
    var linha = this.at().l; this.esperar("word", "criar");
    if (this.ehPal("funcao")) return this.parseFuncao(linha);
    var forma = this.esperar("word");
    var nome = this.esperaNome();
    this.exigeLinha();
    var corpo = this.bloco(["fim"]);
    this.esperar("word", "fim");
    return { tipo: "criar", forma: forma, nome: nome, corpo: corpo, linha: linha };
  };

  Parser.prototype.parseFuncao = function (linha) {
    if (linha == null) linha = this.at().l;
    this.esperar("word", "funcao");
    var nome = this.esperar("word");
    this.esperar("sym", "(");
    var params = [];
    if (!this.eh("sym", ")")) {
      while (true) {
        params.push(this.esperar("word"));
        if (this.eh("sym", ",")) { this.av(); continue; }
        break;
      }
    }
    this.esperar("sym", ")");
    this.exigeLinha();
    var corpo = this.bloco(["fim"]);
    this.esperar("word", "fim");
    return { tipo: "funcao", nome: nome, params: params, corpo: corpo, linha: linha };
  };

  Parser.prototype.parseQuando = function () {
    var linha = this.at().l; this.esperar("word", "quando");
    var partes = [];
    while (!this.fimLinha()) {
      var x = this.at();
      if (x.t === "str" || x.t === "word") { partes.push(x.v); this.av(); }
      else break;
    }
    var evento = null, alvos = [];
    for (var i = 0; i < partes.length; i++) { if (EVENTOS[partes[i]]) { if (!evento) evento = partes[i]; } else alvos.push(partes[i]); }
    this.exigeLinha();
    var corpo = this.bloco(["fim"]);
    this.esperar("word", "fim");
    return { tipo: "quando", evento: evento, alvo: alvos[0] || null, objeto: alvos[1] || null, corpo: corpo, linha: linha };
  };

  Parser.prototype.parseSe = function () {
    var linha = this.at().l; this.esperar("word", "se");
    var ramos = [];
    var cond = this.expressao(); this.exigeLinha();
    var corpo = this.bloco(TERMOS_SE);
    ramos.push({ cond: cond, corpo: corpo });
    var senao = null;
    while (true) {
      if (this.ehPal("senaose")) { this.av(); cond = this.expressao(); this.exigeLinha(); corpo = this.bloco(TERMOS_SE); ramos.push({ cond: cond, corpo: corpo }); }
      else if (this.ehPal("senao") && this.peek(1) && this.peek(1).t === "word" && this.peek(1).v === "se") { this.av(); this.av(); cond = this.expressao(); this.exigeLinha(); corpo = this.bloco(TERMOS_SE); ramos.push({ cond: cond, corpo: corpo }); }
      else if (this.ehPal("senao")) { this.av(); this.exigeLinha(); senao = this.bloco(["fim"]); break; }
      else break;
    }
    this.esperar("word", "fim");
    return { tipo: "se", ramos: ramos, senao: senao, linha: linha };
  };

  Parser.prototype.parseEnquanto = function () {
    var linha = this.at().l; this.esperar("word", "enquanto");
    var cond = this.expressao(); this.exigeLinha();
    var corpo = this.bloco(["fim"]);
    this.esperar("word", "fim");
    return { tipo: "enquanto", cond: cond, corpo: corpo, linha: linha };
  };

  Parser.prototype.parsePara = function () {
    var linha = this.at().l; this.esperar("word", "para"); this.esperar("word", "cada");
    var v = this.esperar("word");
    this.esperar("word", "em");
    var lista = this.expressao(); this.exigeLinha();
    var corpo = this.bloco(["fim"]);
    this.esperar("word", "fim");
    return { tipo: "paracada", var: v, lista: lista, corpo: corpo, linha: linha };
  };

  Parser.prototype.parseACada = function () {
    var linha = this.at().l; this.esperar("word", "a"); this.esperar("word", "cada");
    var intervalo = this.expressao(); this.exigeLinha();
    var corpo = this.bloco(["fim"]);
    this.esperar("word", "fim");
    return { tipo: "acada", intervalo: intervalo, corpo: corpo, linha: linha };
  };

  Parser.prototype.parseRetornar = function () {
    var linha = this.at().l; this.esperar("word", "retornar");
    var valor = this.fimLinha() ? null : this.expressao();
    this.pularNovas();
    return { tipo: "retornar", valor: valor, linha: linha };
  };

  Parser.prototype.parseEsperar = function () {
    var linha = this.at().l; this.esperar("word", "esperar");
    var valor = this.expressao(); this.pularNovas();
    return { tipo: "esperar", valor: valor, linha: linha };
  };

  Parser.prototype.parseMostrar = function () {
    var linha = this.at().l; this.esperar("word", "mostrar");
    var args = this.argsLinha(); this.pularNovas();
    return { tipo: "comando", verbo: "mostrar", args: args, linha: linha };
  };

  Parser.prototype.parseIncluir = function () {
    var linha = this.at().l; this.esperar("word", "incluir");
    var x = this.at();
    if (!x || (x.t !== "str" && x.t !== "word")) this.erro("nome de arquivo esperado após 'incluir'");
    this.av();
    return { tipo: "incluir", caminho: x.v, linha: linha };
  };

  Parser.prototype.argsLinha = function () {
    var args = [];
    while (!this.fimLinha()) {
      var x = this.at();
      if (x.t === "word" && SEPARADORES[x.v]) { args.push({ tipo: "sep", v: x.v }); this.av(); continue; }
      var e = null;
      try { e = this.exprSemLogica(); } catch (err) { e = null; }
      if (!e) { this.av(); continue; }
      args.push({ tipo: "expr", v: e });
    }
    return args;
  };

  Parser.prototype.parseGenerico = function () {
    var inicio = this.i;
    if (this.at() && this.at().t === "word") {
      var alvo = this.tentaLvalue();
      if (alvo && this.eh("sym", "=")) {
        this.av();
        var valor = this.expressao();
        if (!this.fimLinha()) this.erro("texto inesperado no valor da atribuição");
        this.pularNovas();
        return { tipo: "atribuir", alvo: alvo, valor: valor, linha: alvo.linha };
      }
      this.i = inicio;
    }
    var expr = null;
    try { expr = this.expressao(); } catch (e) { expr = null; }
    if (expr && this.fimLinha()) { this.pularNovas(); return { tipo: "expr", valor: expr, linha: expr.linha }; }
    this.i = inicio;
    return this.parseComando();
  };

  Parser.prototype.parseComando = function () {
    var linha = this.at().l;
    var verbo = this.esperar("word");
    var args = this.argsLinha(); this.pularNovas();
    return { tipo: "comando", verbo: verbo, args: args, linha: linha };
  };

  Parser.prototype.tentaLvalue = function () {
    var x = this.at();
    if (!x || x.t !== "word") return null;
    var node = { tipo: "ident", nome: x.v, linha: x.l }; this.av();
    while (true) {
      if (this.eh("sym", ".")) { this.av(); var p = this.esperar("word"); node = { tipo: "acesso", obj: node, prop: p, linha: node.linha }; }
      else if (this.eh("sym", "[")) { this.av(); var idx = this.expressao(); this.esperar("sym", "]"); node = { tipo: "indice", obj: node, idx: idx, linha: node.linha }; }
      else break;
    }
    return node;
  };

  Parser.prototype.expressao = function () { return this.parseExpr(1); };
  Parser.prototype.exprSemLogica = function () { return this.parseExpr(3); };
  Parser.prototype.parseExpr = function (min) {
    var esq = this.unario();
    while (true) {
      var x = this.at(); if (!x) break;
      var op = null;
      if ((x.t === "sym" || x.t === "word") && PREC[x.v] != null) op = x.v;
      if (op === null) break;
      var p = PREC[op];
      if (p < min) break;
      this.av();
      var dir = this.parseExpr(p + (DIREITA[op] ? 0 : 1));
      esq = { tipo: "binario", op: op, esq: esq, dir: dir, linha: esq.linha };
    }
    return esq;
  };
  Parser.prototype.unario = function () {
    var x = this.at();
    if (x && x.t === "sym" && (x.v === "-" || x.v === "+")) { this.av(); return { tipo: "unario", op: x.v, valor: this.unario(), linha: x.l }; }
    if (x && x.t === "word" && (x.v === "nao" || x.v === "not")) { this.av(); return { tipo: "unario", op: "nao", valor: this.unario(), linha: x.l }; }
    return this.posfixo();
  };
  Parser.prototype.posfixo = function () {
    var e = this.primario();
    while (true) {
      var x = this.at(); if (!x) break;
      if (x.t === "sym" && x.v === "(") { this.av(); e = { tipo: "chamada", callee: e, args: this.argumentos(")"), linha: e.linha }; }
      else if (x.t === "sym" && x.v === "[") { this.av(); var idx = this.expressao(); this.esperar("sym", "]"); e = { tipo: "indice", obj: e, idx: idx, linha: e.linha }; }
      else if (x.t === "sym" && x.v === ".") { this.av(); e = { tipo: "acesso", obj: e, prop: this.esperar("word"), linha: e.linha }; }
      else if (x.t === "sym" && x.v === ":") { this.av(); var m = this.esperar("word"); this.esperar("sym", "("); e = { tipo: "metodo", obj: e, metodo: m, args: this.argumentos(")"), linha: e.linha }; }
      else break;
    }
    return e;
  };
  Parser.prototype.argumentos = function (fecho) {
    var args = [];
    if (this.eh("sym", fecho)) { this.av(); return args; }
    while (true) {
      args.push(this.expressao());
      if (this.eh("sym", ",")) { this.av(); continue; }
      break;
    }
    this.esperar("sym", fecho);
    return args;
  };
  Parser.prototype.primario = function () {
    var x = this.at();
    if (!x) this.erro("expressão esperada");
    if (x.t === "num") { this.av(); return { tipo: "num", v: x.v, linha: x.l }; }
    if (x.t === "str") { this.av(); return { tipo: "str", v: x.v, linha: x.l }; }
    if (x.t === "word") {
      if (x.v === "verdadeiro" || x.v === "sim") { this.av(); return { tipo: "bool", v: true, linha: x.l }; }
      if (x.v === "falso") { this.av(); return { tipo: "bool", v: false, linha: x.l }; }
      if (x.v === "nulo" || x.v === "nil") { this.av(); return { tipo: "nulo", linha: x.l }; }
      this.av(); return { tipo: "ident", nome: x.v, linha: x.l };
    }
    if (x.t === "sym" && x.v === "(") {
      this.av();
      var primeiro = this.expressao();
      if (this.eh("sym", ",")) {
        var itens = [primeiro];
        while (this.eh("sym", ",")) { this.av(); itens.push(this.expressao()); }
        this.esperar("sym", ")");
        return { tipo: "vetor", itens: itens, linha: x.l };
      }
      this.esperar("sym", ")");
      return primeiro;
    }
    if (x.t === "sym" && x.v === "[") {
      this.av(); var lista = [];
      if (!this.eh("sym", "]")) { while (true) { lista.push(this.expressao()); if (this.eh("sym", ",")) { this.av(); continue; } break; } }
      this.esperar("sym", "]");
      return { tipo: "lista", itens: lista, linha: x.l };
    }
    if (x.t === "sym" && x.v === "{") {
      this.av(); var pares = [];
      if (!this.eh("sym", "}")) {
        while (true) {
          var k = this.esperar("word");
          if (this.eh("sym", "=") || this.eh("sym", ":")) this.av(); else this.erro("esperava '=' no mapa");
          pares.push([k, this.expressao()]);
          if (this.eh("sym", ",")) { this.av(); continue; } break;
        }
      }
      this.esperar("sym", "}");
      return { tipo: "mapa", pares: pares, linha: x.l };
    }
    this.erro("expressão inesperada '" + x.v + "'");
  };

  function analisar(fonte, toks) {
    var t = toks || require("./lexer").tokenizar(fonte);
    return new Parser(t).parse();
  }

  return { tokenizar: function (f) { return require("./lexer").tokenizar(f); }, analisar: analisar, Parser: Parser };
});
