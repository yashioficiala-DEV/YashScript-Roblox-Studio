(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory(require("./lexer"), require("./parser"), require("./vm"));
  else root.YashLang = factory(root.YashLexer, root.YashParser, root.YashVM);
})(typeof self !== "undefined" ? self : this, function (lexer, parser, vm) {

  function HostMemoria(opts) {
    opts = opts || {};
    this.logs = [];
    this.entidades = [];
    this.comandos = [];
    this.arquivos = opts.arquivos || {};
    this._id = 0;
  }
  HostMemoria.prototype.criar = function (forma, nome) {
    var e = { __y: "handle", id: ++this._id, forma: forma, tipo: forma, nome: nome, props: {} };
    this.entidades.push(e);
    return e;
  };
  HostMemoria.prototype.definir = function (h, k, v) { if (h && h.props) h.props[k] = v; };
  HostMemoria.prototype.obter = function (h, k) { return h && h.props ? h.props[k] : null; };
  HostMemoria.prototype.metodo = function (h, nome, args) { this.comandos.push({ metodo: nome, alvo: h ? h.nome : null, args: args }); return null; };
  HostMemoria.prototype.comando = function (verbo, args, info) {
    var vals = args.filter(function (a) { return !(a && a.sep) && !(a && (a.tipo === "nativo" || a.tipo === "funcao")); });
    this.comandos.push({ verbo: verbo, args: vals, linha: info && info.linha });
    if (verbo === "mostrar") this.logs.push(vals.map(vm.toText).join(" "));
  };
  HostMemoria.prototype.incluir = function (caminho) { return this.arquivos[caminho] || null; };

  function analisar(fonte) { return parser.analisar(fonte, lexer.tokenizar(fonte)); }

  function rodar(fonte, host, opts) {
    var prog = analisar(fonte);
    return vm.executar(prog, host || new HostMemoria(), opts);
  }

  return { lexer: lexer, parser: parser, vm: vm, analisar: analisar, rodar: rodar, HostMemoria: HostMemoria };
});
