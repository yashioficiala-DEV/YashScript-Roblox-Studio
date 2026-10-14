var path = require("path");
var Host = require(path.join(__dirname, "..", "..", "LOGS", "assets", "yash", "yash-engine-host.js"));

var total = 0, falhas = 0;
function ok(nome, cond, extra) { total++; if (cond) { console.log("  ok  " + nome); return true; } falhas++; console.log("  FALHA " + nome + (extra != null ? "  -> " + extra : "")); return false; }
function igual(nome, a, b) { return ok(nome, JSON.stringify(a) === JSON.stringify(b), "recebi " + JSON.stringify(a) + " esperava " + JSON.stringify(b)); }
function grupo(nome, fn) { console.log("\n" + nome + ":"); fn(); }
function vetor(x, y, z) { return { __y: "vetor", x: x, y: y, z: z || 0 }; }
function corat(r, g, b) { return { __y: "cor", r: r, g: g, b: b }; }

function stubEngine() {
  return {
    objs: [], world: { w: 900, h: 520 }, fundo: "#0e1220", gravity: 1400,
    camera: { x: 0, y: 0, zoom: 1, alvo: null, suave: 0 },
    audio: { tocados: [], tocar: function (u, v, l) { this.tocados.push([u, v, l]); return 1; }, parar: function () {} },
    mundo: function (w, h) { this.world = { w: w, h: h }; },
    imagem: function (o, url) { o.url = url; }
  };
}
function montar() {
  var log = [];
  var eng = stubEngine();
  var host = new Host(eng, { registrar: function () { log.push(Array.prototype.slice.call(arguments).join(" ")); } });
  return { eng: eng, host: host, log: log };
}

grupo("criar: formas e defaults", function () {
  var m = montar();
  var chao = m.host.criar("bloco", "chao");
  igual("bloco vira retangulo", chao.obj.tipo, "retangulo");
  igual("entrou em engine.objs", m.eng.objs.length, 1);
  igual("nome no objeto", chao.obj.nome, "chao");
  var bola = m.host.criar("esfera", "bola");
  igual("esfera vira circulo", bola.obj.tipo, "circulo");
  var hud = m.host.criar("hud", "vida");
  igual("hud vira texto", hud.obj.tipo, "texto");
  igual("hud fica no espaco tela", hud.obj.espaco, "tela");
  var jog = m.host.criar("objeto", "jogador");
  igual("objeto logico invisivel", jog.obj.visivel, false);
  igual("objeto logico nao colide", jog.obj.semColisao, true);
});

grupo("definir / obter", function () {
  var m = montar();
  var e = m.host.criar("bloco", "caixa");
  m.host.definir(e, "posicao", vetor(10, 20, 0));
  igual("posicao -> x/y", [e.obj.x, e.obj.y], [10, 20]);
  m.host.definir(e, "tamanho", vetor(40, 8, 0));
  igual("tamanho -> w/h", [e.obj.w, e.obj.h], [40, 8]);
  m.host.definir(e, "cor", corat(255, 80, 80));
  igual("cor -> css rgb", e.obj.cor, "rgb(255, 80, 80)");
  m.host.definir(e, "velocidade", 18);
  igual("velocidade escalar -> vx", [e.obj.vx, e.obj.vy], [18, 0]);
  m.host.definir(e, "velocidade", vetor(3, -4, 0));
  igual("velocidade vetor -> vx/vy", [e.obj.vx, e.obj.vy], [3, -4]);
  m.host.definir(e, "material", "concreto");
  ok("material e no-op (nao vira prop)", !("material" in e.props));
  m.host.definir(e, "vida", 100);
  igual("prop custom em props", m.host.obter(e, "vida"), 100);
  igual("obter posicao", m.host.obter(e, "posicao"), vetor(10, 20, 0));
  igual("obter largura", m.host.obter(e, "largura"), 40);
  igual("obter no_chao default", m.host.obter(e, "no_chao"), false);
});

grupo("metodos", function () {
  var m = montar();
  var a = m.host.criar("bloco", "a");
  var b = m.host.criar("bloco", "b");
  m.host.definir(a, "posicao", vetor(0, 0, 0)); m.host.definir(a, "tamanho", vetor(10, 10, 0));
  m.host.definir(b, "posicao", vetor(5, 5, 0)); m.host.definir(b, "tamanho", vetor(10, 10, 0));
  igual("sobrepor verdadeiro", m.host.metodo(a, "sobrepor", [b]), true);
  m.host.definir(b, "posicao", vetor(100, 100, 0));
  igual("sobrepor falso", m.host.metodo(a, "sobrepor", [b]), false);
  m.host.metodo(a, "mover", [3, 7]);
  igual("mover soma deslocamento", [a.obj.x, a.obj.y], [3, 7]);
  m.host.metodo(b, "destruir", []);
  igual("destruir marca _dead", b.obj._dead, true);
  igual("obter apos destruir -> nulo", m.host.obter(b, "x"), null);
});

grupo("comandos implementados", function () {
  var m = montar();
  m.host.criar("bloco", "alvo");
  m.host.comando("mostrar", [{ tipo: "expr", v: null }, "x"], { linha: 3 });
  m.host.comando("mundo", [800, 600], {});
  igual("mundo aplicado", [m.eng.world.w, m.eng.world.h], [800, 600]);
  m.host.comando("gravidade", [0], {});
  igual("gravidade aplicada", m.eng.gravity, 0);
  m.host.comando("fundo", [corat(10, 20, 30)], {});
  igual("fundo aplicado", m.eng.fundo, "rgb(10, 20, 30)");
  m.host.comando("camera", [50, 60, 2], {});
  igual("camera aplicada", [m.eng.camera.x, m.eng.camera.y, m.eng.camera.zoom], [50, 60, 2]);
  m.host.comando("tocar", ["som.mp3", 0.5, true], {});
  igual("tocar chamou audio", m.eng.audio.tocados[0], ["som.mp3", 0.5, true]);
  m.host.comando("seguir", [m.host.porNome.alvo], {});
  ok("seguir definiu alvo", m.eng.camera.alvo === m.host.porNome.alvo.obj);
});

grupo("comandos nao suportados geram diagnostico", function () {
  var m = montar();
  m.host.comando("sortear", ["bonus"], { linha: 12 });
  ok("registrou nao suportado", /não suportado: sortear/.test(m.log.join("\n")), m.log.join(" | "));
  igual("entrou na lista", m.host.naoSuportados[0].verbo, "sortear");
  ok("nao inventou efeito (objs vazio)", m.eng.objs.length === 0);
});

grupo("incluir avisa e retorna nulo", function () {
  var m = montar();
  var r = m.host.incluir("lib.yash");
  igual("retorno nulo", r, null);
  ok("registrou aviso de incluir", /incluir lib\.yash/.test(m.log.join("\n")), m.log.join(" | "));
});

grupo("nomes duplicados reaproveitam o mesmo no", function () {
  var m = montar();
  var a = m.host.criar("bloco", "x");
  var b = m.host.criar("bloco", "x");
  ok("avisou duplicado", /duplicado/.test(m.log.join("\n")), m.log.join(" | "));
  igual("nenhum no extra criado", m.eng.objs.length, 1);
  ok("os dois handles apontam para o mesmo no", a.obj === b.obj);
  m.host.definir(b, "x", 42);
  igual("escrever por um handle aparece no outro", a.obj.x, 42);
});

grupo("renomear atualiza o mapa de nomes", function () {
  var m = montar();
  var a = m.host.criar("bloco", "x");
  m.host.criar("bloco", "y");
  m.host.definir(a, "nome", "y");
  ok("renomeou no mapa", m.host.porNome.y === a);
  ok("nome antigo liberado", !m.host.porNome.x);
  ok("avisou a colisao de nome", /duplicado/.test(m.log.join("\n")), m.log.join(" | "));
  igual("objeto atualizado", a.obj.nome, "y");
});

grupo("no autorizado na cena nao e duplicado pelo script", function () {
  var m = montar();
  m.eng.objs.push({ id: "n1_ab", nome: "chao", tipo: "retangulo", x: 0, y: 300, w: 900, h: 40, cor: "#3c5a46", estatico: true, deCena: true });
  var chao = m.host.criar("bloco", "chao");
  igual("motor continua com um no", m.eng.objs.length, 1);
  ok("handle reusa o no da cena", chao.obj === m.eng.objs[0]);
  igual("posicao da cena preservada", [chao.obj.x, chao.obj.y], [0, 300]);
  m.host.definir(chao, "cor", corat(255, 80, 80));
  igual("cor da cena editada pelo script", m.eng.objs[0].cor, "rgb(255, 80, 80)");
  ok("avisou que adotou o no da cena", /\[cena\].*usa esse nó/.test(m.log.join("\n")), m.log.join(" | "));
  ok("nao chamou de duplicado", !/duplicado/.test(m.log.join("\n")), m.log.join(" | "));
});

grupo("no destruido libera o nome para um novo", function () {
  var m = montar();
  var a = m.host.criar("bloco", "x");
  m.host.metodo(a, "destruir", []);
  var b = m.host.criar("bloco", "x");
  ok("criou um no novo", a.obj !== b.obj);
  ok("sem aviso de duplicado", !/duplicado/.test(m.log.join("\n")), m.log.join(" | "));
  m.host.definir(b, "x", 7);
  igual("o novo esta vivo", b.obj.x, 7);
});

grupo("escrita apos destruicao avisa e nao altera", function () {
  var m = montar();
  var a = m.host.criar("bloco", "z");
  m.host.definir(a, "x", 5);
  m.host.metodo(a, "destruir", []);
  m.host.definir(a, "x", 99);
  igual("x nao mudou", a.obj.x, 5);
  ok("avisou escrita em destruida", /destruída/.test(m.log.join("\n")), m.log.join(" | "));
});

console.log("\n" + (total - falhas) + " ok, " + falhas + " falhas");
process.exit(falhas ? 1 : 0);
