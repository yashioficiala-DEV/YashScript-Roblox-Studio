var path = require("path");
var base = path.join(__dirname, "..", "..", "LOGS", "assets", "yash");
var YashLang = require(path.join(base, "index.js"));
var Host = require(path.join(base, "yash-engine-host.js"));

var total = 0, falhas = 0;
function ok(nome, cond, extra) { total++; if (cond) { console.log("  ok  " + nome); return true; } falhas++; console.log("  FALHA " + nome + (extra != null ? "  -> " + extra : "")); return false; }
function igual(nome, a, b) { return ok(nome, JSON.stringify(a) === JSON.stringify(b), "recebi " + JSON.stringify(a) + " esperava " + JSON.stringify(b)); }
function grupo(nome, fn) { console.log("\n" + nome + ":"); fn(); }
function stubEngine() {
  return {
    objs: [], world: { w: 400, h: 300 }, fundo: "#0e1220", gravity: 0,
    camera: { x: 0, y: 0, zoom: 1, alvo: null, suave: 0 },
    audio: { tocados: [], tocar: function (u, v, l) { this.tocados.push([u, v, l]); return 1; }, parar: function () {} },
    mundo: function (w, h) { this.world = { w: w, h: h }; }, imagem: function () {}
  };
}
function executar(fonte) {
  var log = [];
  var eng = stubEngine();
  var host = new Host(eng, { registrar: function () { log.push(Array.prototype.slice.call(arguments).join(" ")); } });
  var r = YashLang.rodar(fonte, host);
  return { eng: eng, host: host, r: r, log: log };
}

var PROGRAMA = [
  "criar bloco 'chao'",
  "    posicao = (0, 260)",
  "    tamanho = (400, 30)",
  "    cor = rgb(80, 120, 90)",
  "fim",
  "criar esfera 'bola'",
  "    posicao = (200, 100)",
  "    cor = rgb(255, 80, 80)",
  "fim",
  "quando iniciar",
  "    mostrar texto \"pronto\"",
  "fim",
  "quando apertar_tecla",
  "    mover bola para (10, 20)",
  "fim",
  "a cada 1",
  "    mostrar texto \"tique\"",
  "fim"
].join("\n");

grupo("execucao nativa basica", function () {
  var m = executar(PROGRAMA);
  igual("duas entidades criadas", m.eng.objs.length, 2);
  var chao = m.host.porNome.chao.obj, bola = m.host.porNome.bola.obj;
  igual("chao posicao", [chao.x, chao.y], [0, 260]);
  igual("chao tamanho", [chao.w, chao.h], [400, 30]);
  igual("bola cor", bola.cor, "rgb(255, 80, 80)");
  igual("bola posicao inicial", [bola.x, bola.y], [200, 100]);
});

grupo("evento iniciar", function () {
  var m = executar(PROGRAMA);
  igual("nada antes de iniciar", m.log, []);
  m.r.emitir("iniciar");
  igual("mostrar ao iniciar", m.log, ["pronto"]);
});

grupo("evento de tecla move a entidade", function () {
  var m = executar(PROGRAMA);
  m.r.emitir("apertar_tecla");
  igual("bola reposicionada", [m.host.porNome.bola.obj.x, m.host.porNome.bola.obj.y], [10, 20]);
});

grupo("timer a cada respeita o relogio virtual", function () {
  var m = executar(PROGRAMA);
  m.r.passo(0.5);
  igual("nada antes de 1s", m.log, []);
  m.r.passo(0.5);
  igual("tique em 1s", m.log, ["tique"]);
  m.r.passo(1.0);
  igual("segundo tique em 2s", m.log, ["tique", "tique"]);
});

grupo("esperar (corrotina) com relogio virtual", function () {
  var m = executar("criar bloco 'bola'\nfim\nquando iniciar\n    mover bola para (500, 100)\n    esperar 0.5\n    mover bola para (900, 100)\nfim");
  m.r.emitir("iniciar");
  igual("moveu antes do esperar", [m.host.porNome.bola.obj.x, m.host.porNome.bola.obj.y], [500, 100]);
  m.r.passo(0.3);
  igual("ainda em 500 durante espera", m.host.porNome.bola.obj.x, 500);
  m.r.passo(0.3);
  igual("moveu apos esperar", m.host.porNome.bola.obj.x, 900);
});

grupo("reinicio limpa entidades e tarefas", function () {
  var m1 = executar(PROGRAMA);
  m1.r.emitir("iniciar"); m1.r.passo(1);
  var m2 = executar("criar bloco 'so'\n    posicao = (5, 5)\nfim");
  igual("novo motor comeca limpo", m2.eng.objs.length, 1);
  igual("sem tarefas da execucao anterior", m2.r.rt.vivas(), 0);
  m2.r.passo(1);
  igual("tarefas antigas nao disparam no novo", m2.log, []);
});

grupo("erro de execucao com linha", function () {
  var e = null;
  try { executar("criar bloco 'x'\nfim\nmostrar x(1)"); } catch (err) { e = err; }
  ok("lancou erro", e && /não é função/.test(e.erro), JSON.stringify(e));
  ok("traz linha", e && e.linha === 3, e && e.linha);
});

grupo("comando nao suportado nao cria efeito", function () {
  var m = executar("sortear bonus entre 1 e 9");
  ok("diagnosticou", /não suportado: sortear/.test(m.log.join("\n")), m.log.join(" | "));
  igual("nenhuma entidade criada", m.eng.objs.length, 0);
});

console.log("\n" + (total - falhas) + " ok, " + falhas + " falhas");
process.exit(falhas ? 1 : 0);
