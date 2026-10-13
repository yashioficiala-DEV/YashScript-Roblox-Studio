var path = require("path");
var YashLang = require(path.join(__dirname, "..", "..", "LOGS", "assets", "yash", "index.js"));
var lexer = YashLang.lexer, parser = YashLang.parser, vm = YashLang.vm;

var total = 0, falhas = 0;
function ok(nome, cond, extra) {
  total++;
  if (cond) { console.log("  ok  " + nome); return true; }
  falhas++;
  console.log("  FALHA " + nome + (extra != null ? "  -> " + extra : ""));
  return false;
}
function igual(nome, a, b) { return ok(nome, JSON.stringify(a) === JSON.stringify(b), "recebi " + JSON.stringify(a) + " esperava " + JSON.stringify(b)); }
function grupo(nome, fn) { console.log("\n" + nome + ":"); fn(); }

grupo("lexer", function () {
  var t = lexer.tokenizar("x = 1.5 + 2\n# comentario\n'oi'");
  var tipos = t.map(function (x) { return x.t; });
  igual("tipos", tipos, ["word", "sym", "num", "sym", "num", "new", "new", "str", "eof"]);
  ok("linha da string", t[7].l === 3, t[7].l);
  var e = null;
  try { lexer.tokenizar('nome = "sem fim'); } catch (err) { e = err; }
  ok("string sem fechar acusa linha", e && e.linha === 1, JSON.stringify(e));
});

grupo("parser", function () {
  var prog = parser.analisar("criar bloco 'chao'\n    x = 1\nfim\nquando clicar 'btn'\n    mostrar 1\nfim");
  igual("duas declaracoes", prog.corpo.length, 2);
  igual("tipo criar", prog.corpo[0].tipo, "criar");
  igual("forma", prog.corpo[0].forma, "bloco");
  igual("nome", prog.corpo[0].nome, "chao");
  igual("tipo quando", prog.corpo[1].tipo, "quando");
  igual("evento", prog.corpo[1].evento, "clicar");
  igual("alvo", prog.corpo[1].alvo, "btn");
  var se = parser.analisar("se 1 < 2\n    mostrar 1\nsenao\n    mostrar 2\nfim");
  igual("se tem senao", se.corpo[0].senao != null, true);
  var nl = parser.analisar("se 5 menor que 10\n    mostrar 1\nfim");
  igual("alias 'menor que' vira '<'", nl.corpo[0].ramos[0].cond.op, "<");
  var e = null;
  try { parser.analisar("se\nmostrar 1\nfim"); } catch (err) { e = err; }
  ok("erro de sintaxe com linha", e && e.linha >= 1, JSON.stringify(e));
});

grupo("vm: expressoes e variaveis", function () {
  var h = new YashLang.HostMemoria();
  YashLang.rodar("a = 2\nb = 3 * (a + 1)\nmostrar b\nmostrar 'total ' .. b", h);
  igual("precedencia e concat", h.logs, ["9", "total 9"]);
  var h2 = new YashLang.HostMemoria();
  YashLang.rodar("mostrar 2 ^ 3 ^ 2\nmostrar 7 % 4\nmostrar 7 // 2", h2);
  igual("potencia a direita, mod, div inteira", h2.logs, ["512", "3", "3"]);
});

grupo("vm: funcoes", function () {
  var h = new YashLang.HostMemoria();
  YashLang.rodar("funcao dobro(x)\n    retornar x * 2\nfim\nmostrar dobro(21)", h);
  igual("chamada de funcao", h.logs, ["42"]);
});

grupo("vm: controle de fluxo", function () {
  var h = new YashLang.HostMemoria();
  YashLang.rodar("i = 0\nenquanto i < 3\n    i = i + 1\nfim\nmostrar i", h);
  igual("enquanto", h.logs, ["3"]);
  var h2 = new YashLang.HostMemoria();
  YashLang.rodar("total = 0\npara cada n em [1, 2, 3, 4]\n    total = total + n\nfim\nmostrar total", h2);
  igual("para cada soma lista", h2.logs, ["10"]);
  var h3 = new YashLang.HostMemoria();
  YashLang.rodar("idade = 20\nse idade maior que 18\n    mostrar 'maior'\nsenao\n    mostrar 'menor'\nfim", h3);
  igual("se com alias NL", h3.logs, ["maior"]);
});

grupo("vm: entidades e propriedades", function () {
  var h = new YashLang.HostMemoria();
  YashLang.rodar("criar bloco 'chao'\n    x = 10\n    largura = 40\nfim\nmostrar chao.largura", h);
  igual("entidade criada", h.entidades.length, 1);
  igual("forma da entidade", h.entidades[0].forma, "bloco");
  igual("nome da entidade", h.entidades[0].nome, "chao");
  igual("atribuicao vira propriedade", h.entidades[0].props.largura, 40);
  igual("acesso a propriedade", h.logs, ["40"]);
});

grupo("vm: eventos e tempo virtual", function () {
  var h = new YashLang.HostMemoria();
  var r = YashLang.rodar("quando iniciar\n    mostrar 'inicio'\n    esperar 1\n    mostrar 'fim'\nfim", h);
  igual("nada antes de iniciar", h.logs, []);
  r.iniciar();
  igual("roda ate o esperar", h.logs, ["inicio"]);
  r.passo(0.5);
  igual("ainda esperando em 0.5s", h.logs, ["inicio"]);
  r.passo(0.6);
  igual("retoma depois de 1s", h.logs, ["inicio", "fim"]);
});

grupo("vm: a cada (timer)", function () {
  var h = new YashLang.HostMemoria();
  var r = YashLang.rodar("contador = 0\na cada 0.5\n    contador = contador + 1\n    mostrar contador\nfim", h);
  r.passo(0.5);
  igual("primeiro tique", h.logs, ["1"]);
  r.passo(0.5);
  igual("segundo tique", h.logs, ["1", "2"]);
});

grupo("vm: valores nativos", function () {
  var h = new YashLang.HostMemoria();
  YashLang.rodar("c = rgb(255, 128, 0)\nmostrar c\nv = vetor(1, 2)\nmostrar v\nmostrar distancia(vetor(0,0), vetor(3,4))", h);
  igual("cor e vetor e distancia", h.logs, ["rgb(255, 128, 0)", "(1, 2, 0)", "5"]);
});

grupo("vm: erro de execucao com linha", function () {
  var e = null;
  try { YashLang.rodar("mostrar foo(1)\nmostrar 2", new YashLang.HostMemoria()); } catch (err) { e = err; }
  ok("erro ao chamar nao-funcao", e && /não é função/.test(e.erro), JSON.stringify(e));
  ok("linha do erro", e && e.linha === 1, e && e.linha);
});

grupo("vm: incluir", function () {
  var h = new YashLang.HostMemoria({ arquivos: { "lib.yash": parser.analisar("funcao triplo(x)\n    retornar x * 3\nfim") } });
  YashLang.rodar("incluir 'lib.yash'\nmostrar triplo(5)", h);
  igual("funcao vinda de incluir", h.logs, ["15"]);
});

console.log("\n" + (total - falhas) + " ok, " + falhas + " falhas");
process.exit(falhas ? 1 : 0);
