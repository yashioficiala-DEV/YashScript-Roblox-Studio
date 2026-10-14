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
      c.createRadialGradient = c.createLinearGradient = function () { return { addColorStop: function () {} }; };
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
ev("window.YashAuth={aoPronto:function(cb){cb({usuario:{id:'u1',nome:'Teste'}});},carregarProjeto:function(){return Promise.resolve({nome:'p',codigo:''});},salvarProjeto:function(id,d){(window.__salvos||(window.__salvos=[])).push(d);return Promise.resolve();},sair:function(){}};");
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
  var alvo = itens.filter(function (n) { return n.textContent.trim() === "Modo: YashScript"; })[0];
  ok("item de menu Modo: YashScript existe", !!alvo);
  if (alvo) alvo.click();

  dbg = win.__yashDebug();
  ok("modo mudou para yashnativo", dbg && dbg.modo === "yashnativo", dbg && dbg.modo);
  ok("estudio abre parado", dbg && dbg.emExecucao === false, JSON.stringify(dbg));
  ok("parado nao ha entidades", dbg && dbg.objs === 0, dbg && dbg.objs);

  doc.getElementById("rodar").click();
  dbg = win.__yashDebug();
  ok("rodar cria as duas entidades", dbg && dbg.emExecucao === true && dbg.objs === 2, JSON.stringify(dbg));

  for (var k = 0; k < 5; k++) { var cb = win.__frames.shift(); if (cb) cb(16.7 * (k + 1)); }
  dbg = win.__yashDebug();
  ok("ainda 2 entidades apos frames", dbg && dbg.objs === 2, dbg && dbg.objs);

  var errEl = doc.getElementById("erro");
  ok("sem erro exibido", errEl.style.display === "none" || errEl.textContent === "", errEl.textContent);
  ok("sem excecao no loader", erros.length === 0, erros.join(" | "));
  var tree = doc.getElementById("tree");
  ok("arvore populada", tree && tree.textContent.indexOf("bola") >= 0, tree && tree.textContent.slice(0, 80));

  // --- modelo de cena: autorar no, editar no inspetor, salvar, executar sem estragar a cena ---
  function campoDe(prefixo) {
    var linhas = Array.prototype.slice.call(doc.querySelectorAll("#inspector .insp-row"));
    var l = linhas.filter(function (r) { return r.textContent.indexOf(prefixo) === 0; })[0];
    return l && l.querySelector("input, select");
  }
  var tela = doc.getElementById("tela");
  function mouse(type, x, y, extras) {
    var o = { clientX: x, clientY: y, button: 0, bubbles: true };
    if (extras) for (var k in extras) o[k] = extras[k];
    tela.dispatchEvent(new win.MouseEvent(type, o));
  }
  function tecla(key, extras) {
    var o = { key: key, bubbles: true };
    if (extras) for (var k in extras) o[k] = extras[k];
    win.dispatchEvent(new win.KeyboardEvent("keydown", o));
  }

  doc.getElementById("parar").click();
  dbg = win.__yashDebug();
  ok("parar volta para a cena", dbg && dbg.emExecucao === false && dbg.nos === 0, JSON.stringify(dbg));
  ok("cena vazia na arvore", doc.getElementById("tree").textContent.indexOf("Cena") >= 0, doc.getElementById("tree").textContent);
  var ferramentas = Array.prototype.slice.call(doc.querySelectorAll("#treeTools button"));
  ok("sem botoes de criar no topo da arvore (vao para o botao direito)", ferramentas.length === 0, ferramentas.length);

  function abrirCenaMenuEAcionar(rot) {
    var menus = Array.prototype.slice.call(doc.querySelectorAll(".menu > button"));
    var cenaBtn = menus.filter(function (b) { return b.textContent.trim() === "Cena"; })[0];
    if (cenaBtn) cenaBtn.click();
    var pop = Array.prototype.slice.call(doc.querySelectorAll(".menu-pop button"));
    var item = pop.filter(function (b) { return b.textContent.trim().indexOf(rot) === 0; })[0];
    if (item) item.click();
  }
  function adicionarNoViaDialogo(nomeTipo) {
    abrirCenaMenuEAcionar("Adicionar nó…");
    var tipo = Array.prototype.slice.call(doc.querySelectorAll(".dlg-lista button"))
      .filter(function (b) { var s = b.querySelector("span"); return s && s.textContent.trim() === nomeTipo; })[0];
    if (tipo) tipo.click();
    var adicionar = Array.prototype.slice.call(doc.querySelectorAll(".dlg-actions button"))
      .filter(function (b) { return b.textContent.trim() === "Adicionar"; })[0];
    if (adicionar) adicionar.click();
  }
  adicionarNoViaDialogo("esfera");
  dbg = win.__yashDebug();
  ok("adicionar esfera cria um no na cena", dbg && dbg.nos === 1, dbg && dbg.nos);
  ok("no novo ja esta selecionado no inspetor", !!campoDe("Nome"), doc.getElementById("inspector").textContent.slice(0, 60));
  ok("editar a cena marca alteracoes", dbg && dbg.dirty === true);

  var campoX = campoDe("Posi");
  campoX.value = "123";
  campoX.dispatchEvent(new win.Event("input", { bubbles: true }));
  dbg = win.__yashDebug();
  ok("inspetor escreveu no no da cena", dbg && dbg.cena.objetos[0].x === 123, dbg && dbg.cena.objetos[0].x);

  // --- wireframe: selecionar, arrastar, alcas, teclado ---
  mouse("mousedown", 141, 260);            // centro do no (123..159, 242..278)
  mouse("mousemove", 200, 300);
  mouse("mouseup", 200, 300);
  dbg = win.__yashDebug();
  ok("arrastar no wireframe move o no da cena", dbg && dbg.cena.objetos[0].x === 182 && dbg.cena.objetos[0].y === 282, JSON.stringify(dbg.cena.objetos[0]));

  mouse("mousedown", 218, 318);           // alca sudeste
  mouse("mousemove", 238, 338);
  mouse("mouseup", 238, 338);
  dbg = win.__yashDebug();
  ok("arrastar a alca redimensiona o no", dbg && dbg.cena.objetos[0].w === 56 && dbg.cena.objetos[0].h === 56, JSON.stringify(dbg.cena.objetos[0]));
  ok("redimensionar nao moveu o canto oposto", dbg && dbg.cena.objetos[0].x === 182 && dbg.cena.objetos[0].y === 282, JSON.stringify(dbg.cena.objetos[0]));

  mouse("mousedown", 182, 310);           // alca oeste: so a borda esquerda
  mouse("mousemove", 162, 330);
  mouse("mouseup", 162, 330);
  dbg = win.__yashDebug();
  ok("alca oeste estica para o oeste", dbg && dbg.cena.objetos[0].x === 162 && dbg.cena.objetos[0].w === 76, JSON.stringify(dbg.cena.objetos[0]));
  ok("alca oeste nao mexe na base", dbg && dbg.cena.objetos[0].y === 282 && dbg.cena.objetos[0].h === 56, JSON.stringify(dbg.cena.objetos[0]));

  mouse("mousedown", 162, 338);           // alca sudoeste: canto (162..238, 282..338)
  mouse("mousemove", 142, 358);
  mouse("mouseup", 142, 358);
  dbg = win.__yashDebug();
  ok("alca sudoeste arrasta a esquerda junto", dbg && dbg.cena.objetos[0].x === 142 && dbg.cena.objetos[0].w === 96, JSON.stringify(dbg.cena.objetos[0]));
  ok("alca sudoeste mantem o topo e estica a base", dbg && dbg.cena.objetos[0].y === 282 && dbg.cena.objetos[0].h === 76, JSON.stringify(dbg.cena.objetos[0]));

  mouse("mousedown", 700, 60);            // vazio
  mouse("mouseup", 700, 60);
  dbg = win.__yashDebug();
  ok("clicar no vazio desmarca", dbg && dbg.selecionado === null, JSON.stringify(dbg.selecionado));

  mouse("mousedown", 210, 310);           // re-seleciona pelo canvas
  mouse("mouseup", 210, 310);
  dbg = win.__yashDebug();
  ok("clicar no no seleciona pelo canvas", dbg && dbg.selecionado && dbg.selecionado.nome === "bola", JSON.stringify(dbg.selecionado));
  tecla("ArrowRight", { shiftKey: true });
  dbg = win.__yashDebug();
  ok("seta com shift empurra na grade", dbg && dbg.cena.objetos[0].x === 182, dbg && dbg.cena.objetos[0].x);
  tecla("ArrowLeft");
  dbg = win.__yashDebug();
  ok("seta sozinho empurra 1 pixel", dbg && dbg.cena.objetos[0].x === 181, dbg && dbg.cena.objetos[0].x);

  doc.getElementById("salvar").click();
  var salvo = (win.__salvos || [])[0];
  ok("salvar envia as cenas junto", !!salvo && Array.isArray(salvo.cenas) && salvo.cenas[0].objetos.length === 1, JSON.stringify(salvo && salvo.cenas));
  ok("o projeto salvo traz a dimensao", !!salvo && (salvo.dim === "2d" || salvo.dim === "3d"), salvo && salvo.dim);
  ok("a cena salva traz o no editado no wireframe", !!salvo && salvo.cenas[0].objetos[0].nome === "bola" && salvo.cenas[0].objetos[0].x === 181 && salvo.cenas[0].objetos[0].w === 96, JSON.stringify(salvo && salvo.cenas[0].objetos[0]));

  doc.getElementById("rodar").click();
  dbg = win.__yashDebug();
  ok("execucao reusa o no da cena (2 nos, nao 3)", dbg && dbg.emExecucao === true && dbg.objs === 2, JSON.stringify(dbg));
  ok("saida explica que o no da cena foi adotado", doc.getElementById("log").textContent.indexOf("já existia na cena") >= 0, doc.getElementById("log").textContent);

  // edicao ao vivo durante a execucao: bola esta em (120,40) tamanho 36 (o script mandou para la)
  var dirtyAntes = win.__yashDebug().dirty;
  mouse("mousedown", 138, 58);
  mouse("mousemove", 188, 108);
  mouse("mouseup", 188, 108);
  dbg = win.__yashDebug();
  ok("arrastar durante a execucao move o corpo vivo", dbg && dbg.selecionado && dbg.selecionado.x === 170 && dbg.selecionado.y === 90, JSON.stringify(dbg.selecionado));
  ok("editar na execucao nao grava na cena", dbg && dbg.cena.objetos[0].x === 181 && dbg.dirty === dirtyAntes, JSON.stringify(dbg.cena.objetos[0]) + " dirty=" + dbg.dirty);

  doc.getElementById("parar").click();
  dbg = win.__yashDebug();
  ok("executar e arrastar nao alteram a cena autorada", dbg && dbg.cena.objetos[0].x === 181, dbg && dbg.cena.objetos[0].x);
  ok("parar volta a mostrar so a cena", dbg && dbg.objs === 1 && dbg.nos === 1, JSON.stringify(dbg));

  doc.getElementById("rodar").click();
  adicionarNoViaDialogo("bloco");
  dbg = win.__yashDebug();
  ok("mexer na cena durante a execucao para o jogo", dbg && dbg.emExecucao === false && dbg.nos === 2, JSON.stringify(dbg));

  tecla("Delete");
  dbg = win.__yashDebug();
  ok("Delete remove o no selecionado", dbg && dbg.nos === 1 && dbg.cena.objetos[0].nome === "bola", JSON.stringify(dbg.cena.objetos.map(function (o) { return o.nome; })));

  // --- nos 3D desenham sem explodir (isometrico + esfera com gradiente) ---
  var erro3d = null;
  try {
    var cv3 = doc.createElement("canvas"); cv3.width = 400; cv3.height = 300;
    var eng3 = new win.YashWeb.Engine(cv3);
    eng3.carregar({ objetos: [
      { tipo: "box3d", x: 40, y: 40, w: 80, h: 80, profundidade: 60, cor: "#5b8bff" },
      { tipo: "plano3d", x: 150, y: 120, w: 120, h: 60, profundidade: 8, cor: "#3c5a46" },
      { tipo: "cilindro3d", x: 220, y: 60, w: 40, h: 90, profundidade: 40, cor: "#e8c46a" },
      { tipo: "esfera3d", x: 60, y: 180, w: 50, h: 50, profundidade: 50, cor: "#ff785a" },
      { tipo: "modelo3d", x: 300, y: 200, w: 60, h: 60, profundidade: 60, cor: "#9ab0d8" }
    ] });
    eng3.update(0);
  } catch (e) { erro3d = (e && e.message) || String(e); }
  ok("nos 3D desenham sem erro", erro3d === null, erro3d);

  console.log("\n" + (total - falhas) + " ok, " + falhas + " falhas");
  process.exit(falhas ? 1 : 0);
}, 200);
