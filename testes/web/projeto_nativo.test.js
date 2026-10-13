var fs = require("fs");
var path = require("path");
var JSDOM;
try { JSDOM = require("jsdom").JSDOM; }
catch (e) { console.log("SKIP projeto_nativo.test.js: jsdom nao instalado (npm install)."); process.exit(0); }

var ROOT = path.join(__dirname, "..", "..", "LOGS");
var html = fs.readFileSync(path.join(ROOT, "projeto.html"), "utf8");
var appM = html.match(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/);
if (!appM) { console.log("FALHA: script inline nao encontrado"); process.exit(1); }
var appJs = appM[1];
var htmlSemScripts = html.replace(/<script[\s\S]*?<\/script>/g, "");
function ler(p) { return fs.readFileSync(path.join(ROOT, p), "utf8"); }

var total = 0, falhas = 0;
function ok(nome, cond, extra) { total++; if (cond) { console.log("  ok  " + nome); return; } falhas++; console.log("  FALHA " + nome + (extra != null ? "  -> " + extra : "")); }

var erros = [];
var dom = new JSDOM(htmlSemScripts, {
  url: "http://localhost/projeto.html?id=teste",
  runScripts: "outside-only",
  pretendToBeVisual: true,
  beforeParse: function (window) {
    window.__frames = [];
    window.requestAnimationFrame = function (cb) { window.__frames.push(cb); return window.__frames.length; };
    window.cancelAnimationFrame = function () {};
    window.HTMLCanvasElement.prototype.getContext = function () {
      var self = this, c = {};
      ["setTransform", "fillRect", "clearRect", "strokeRect", "save", "restore", "translate", "scale", "rotate",
        "beginPath", "arc", "fill", "moveTo", "lineTo", "closePath", "stroke", "fillText", "drawImage", "rect",
        "ellipse", "clip", "quadraticCurveTo", "bezierCurveTo"].forEach(function (k) { c[k] = function () {}; });
      c.canvas = self;
      return c;
    };
    window.addEventListener("error", function (e) { erros.push(String((e.error && e.error.stack) || e.message)); });
  }
});
var win = dom.window;
function ev(code) { try { win.eval(code); } catch (e) { erros.push("eval: " + ((e && e.stack) || e)); } }

ev(ler(path.join("assets", "engine.js")));
ev(ler(path.join("assets", "yash", "lexer.js")));
ev(ler(path.join("assets", "yash", "parser.js")));
ev(ler(path.join("assets", "yash", "vm.js")));
ev(ler(path.join("assets", "yash", "index.js")));
ev(ler(path.join("assets", "yash", "yash-engine-host.js")));
ev("window.fengari={lua:{},lauxlib:{},lualib:{},to_luastring:function(){return [];}};");
ev("window.YashAuth={aoPronto:function(cb){cb({usuario:{id:'u1',nome:'Teste'}});},carregarProjeto:function(){return Promise.resolve({nome:'p',codigo:''});},salvarProjeto:function(){return Promise.resolve();},sair:function(){}};");
ev("window.YashUI={chip:function(){},exigirLogin:function(){return Promise.resolve();}};");
ev("window.fetch=function(){return Promise.reject(new Error('offline'));};");
ev(appJs);

setTimeout(function () {
  var doc = win.document;
  var dbg = win.__yashDebug ? win.__yashDebug() : null;
  ok("modo inicial yashnativo", dbg && dbg.modo === "yashnativo", dbg && dbg.modo);

  var codeEl = doc.getElementById("codigo");
  codeEl.value = "criar bloco 'chao'\n    posicao = (0, 250)\n    tamanho = (400, 30)\nfim\ncriar esfera 'bola'\n    posicao = (200, 100)\n    cor = rgb(255, 80, 80)\nfim\nquando iniciar\n    mover bola para (120, 40)\nfim";

  var itens = Array.prototype.slice.call(doc.querySelectorAll(".menu-pop button"));
  var alvo = itens.filter(function (n) { return n.textContent.trim() === "YashScript"; })[0];
  ok("item de menu YashScript existe", !!alvo);
  if (alvo) alvo.click();

  dbg = win.__yashDebug();
  ok("modo mudou para yashnativo", dbg && dbg.modo === "yashnativo", dbg && dbg.modo);
  ok("duas entidades no motor", dbg && dbg.objs === 2, dbg && dbg.objs);

  for (var k = 0; k < 5; k++) { var cb = win.__frames.shift(); if (cb) cb(16.7 * (k + 1)); }
  dbg = win.__yashDebug();
  ok("ainda 2 entidades apos frames", dbg && dbg.objs === 2, dbg && dbg.objs);

  var errEl = doc.getElementById("erro");
  ok("sem erro exibido", errEl.style.display === "none" || errEl.textContent === "", errEl.textContent);
  ok("sem excecao no loader", erros.length === 0, erros.join(" | "));
  var tree = doc.getElementById("tree");
  ok("arvore populada", tree && tree.textContent.indexOf("bola") >= 0, tree && tree.textContent.slice(0, 80));

  console.log("\n" + (total - falhas) + " ok, " + falhas + " falhas");
  process.exit(falhas ? 1 : 0);
}, 200);
