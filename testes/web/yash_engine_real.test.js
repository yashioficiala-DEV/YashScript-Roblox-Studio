var path = require("path");
var base = path.join(__dirname, "..", "..", "LOGS", "assets");
var YashLang = require(path.join(base, "yash", "index.js"));
var Host = require(path.join(base, "yash", "yash-engine-host.js"));
var YashWeb = require(path.join(base, "engine.js"));

var total = 0, falhas = 0;
function ok(nome, cond, extra) { total++; if (cond) { console.log("  ok  " + nome); return true; } falhas++; console.log("  FALHA " + nome + (extra != null ? "  -> " + extra : "")); return false; }
function igual(nome, a, b) { return ok(nome, JSON.stringify(a) === JSON.stringify(b), "recebi " + JSON.stringify(a) + " esperava " + JSON.stringify(b)); }
function grupo(nome, fn) { console.log("\n" + nome + ":"); fn(); }

function fakeCanvas() {
  var cv = { width: 400, height: 300 };
  cv.getContext = function () {
    var c = { canvas: cv, fillStyle: "", strokeStyle: "", lineWidth: 1, font: "", textAlign: "", textBaseline: "", globalAlpha: 1 };
    var noop = function () {};
    ["setTransform", "fillRect", "clearRect", "strokeRect", "save", "restore", "translate", "scale", "rotate",
      "beginPath", "arc", "fill", "moveTo", "lineTo", "closePath", "stroke", "fillText", "drawImage",
      "rect", "ellipse", "clip", "quadraticCurveTo", "bezierCurveTo"].forEach(function (k) { c[k] = noop; });
    return c;
  };
  return cv;
}
function rodarNoMotor(fonte) {
  var engine = new YashWeb.Engine(fakeCanvas());
  engine.carregar({ largura: 400, altura: 300, fundo: "#0b0f1a", gravidade: 0 });
  var log = [];
  var host = new Host(engine, { aabb: YashWeb.aabb, registrar: function () { log.push(Array.prototype.slice.call(arguments).join(" ")); } });
  var r = YashLang.rodar(fonte, host);
  return { engine: engine, host: host, r: r, log: log };
}
function achar(engine, nome) { return engine.objs.filter(function (o) { return o.nome === nome && !o._dead; })[0]; }

grupo("host real cria entidades visiveis no motor", function () {
  var m = rodarNoMotor("criar bloco 'chao'\n    posicao = (0, 250)\n    tamanho = (400, 30)\n    cor = rgb(80, 120, 90)\nfim\ncriar esfera 'bola'\n    posicao = (200, 100)\n    cor = rgb(255, 80, 80)\nfim");
  igual("duas entidades no motor", m.engine.objs.length, 2);
  var chao = achar(m.engine, "chao"), bola = achar(m.engine, "bola");
  igual("chao tipo", chao.tipo, "retangulo");
  igual("bola tipo", bola.tipo, "circulo");
  igual("bola posicao", [bola.x, bola.y], [200, 100]);
  igual("bola cor", bola.cor, "rgb(255, 80, 80)");
});

grupo("engine.update executa (integra + resolve + render) sem lançar", function () {
  var m = rodarNoMotor("criar bloco 'caixa'\n    posicao = (10, 10)\n    tamanho = (40, 40)\nfim");
  var erro = null;
  try { m.r.passo(1 / 60); m.engine.update(1 / 60); } catch (e) { erro = e; }
  ok("update sem erro", !erro, erro && erro.stack);
});

grupo("script altera posicao e cor; motor reflete", function () {
  var m = rodarNoMotor("criar bloco 'p'\n    posicao = (0, 0)\nfim\nquando iniciar\n    mover p para (120, 60)\n    p.cor = rgb(0, 0, 255)\nfim");
  m.r.emitir("iniciar");
  var p = achar(m.engine, "p");
  igual("posicao alterada pelo script", [p.x, p.y], [120, 60]);
  igual("cor alterada pelo script", p.cor, "rgb(0, 0, 255)");
});

grupo("entidade destruida some do motor", function () {
  var m = rodarNoMotor("criar bloco 'x'\n    posicao = (0, 0)\nfim\nquando iniciar\n    x:destruir()\nfim");
  m.r.emitir("iniciar");
  ok("marcada como morta", achar(m.engine, "x") === undefined);
  m.engine.update(1 / 60);
  igual("removida de objs apos update", m.engine.objs.length, 0);
});

grupo("fisica do motor move corpo com velocidade", function () {
  var m = rodarNoMotor("criar esfera 'b'\n    posicao = (0, 0)\n    velocidade = (60, 0)\nfim");
  m.engine.update(0.5);
  var b = achar(m.engine, "b");
  ok("avancou no eixo x", b.x > 20, b.x);
});

grupo("reinicio: novo motor sem residuos", function () {
  var m1 = rodarNoMotor("criar bloco 'a'\nfim\nquando iniciar\n    mostrar texto \"1\"\nfim");
  m1.r.emitir("iniciar");
  var m2 = rodarNoMotor("criar bloco 'b'\nfim");
  igual("novo motor so com 'b'", m2.engine.objs.length, 1);
  igual("sem entidade 'a'", achar(m2.engine, "a"), undefined);
});

grupo("audio: tocar usa o construtor nativo de som e devolve id", function () {
  var tocados = [];
  function FakeAudio(url) {
    this.src = url; this.volume = 0; this.loop = false; this._fims = [];
    this.play = function () { tocados.push(this); return Promise.resolve(); };
    this.pause = function () { this.paused = true; };
    this.addEventListener = function (_, fn) { this._fims.push(fn); };
  }
  var antes = globalThis.Audio;
  globalThis.Audio = FakeAudio;
  delete require.cache[path.join(base, "engine.js")];
  var WebReal = require(path.join(base, "engine.js"));
  var eng = new WebReal.Engine(fakeCanvas());
  var id = eng.audio.tocar("som/pulo.mp3", 0.5, false);
  ok("tocar devolve id", typeof id === "number" && id > 0, id);
  igual("elemento criado com a url", tocados.length === 1 && tocados[0].src, "som/pulo.mp3");
  igual("volume aplicado", tocados.length && tocados[0].volume, 0.5);
  eng.audio.parar(id);
  ok("parar pausa o elemento", tocados.length === 1 && tocados[0].paused === true, tocados.length && tocados[0].paused);
  igual("sem audio nativo tocar devolve null", (function () {
    globalThis.Audio = antes;
    delete require.cache[path.join(base, "engine.js")];
    var SemSom = require(path.join(base, "engine.js"));
    return new SemSom.Engine(fakeCanvas()).audio.tocar("a.mp3");
  })(), null);
  delete require.cache[path.join(base, "engine.js")];
  require(path.join(base, "engine.js"));
});

console.log("\n" + (total - falhas) + " ok, " + falhas + " falhas");
process.exit(falhas ? 1 : 0);
