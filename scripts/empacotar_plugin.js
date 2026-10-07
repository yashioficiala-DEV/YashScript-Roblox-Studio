// Empacota o plugin YashScript: lê o núcleo (compilador + gerador) e o modelo,
// e gera plugin/plugin.lua com os fontes embutidos como
// strings (via HttpService:JSONDecode) prontos para instalar.
const fs = require("fs");
const path = require("path");

const raiz = path.join(__dirname, "..");
function ler(rel) {
  return fs.readFileSync(path.join(raiz, rel), "utf8").replace(/\r\n/g, "\n");
}

function luaString(s) {
  // gera um literal de string Lua (entre aspas) cujo conteúdo é o JSON de s
  const json = JSON.stringify(s);
  return '"' + json.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

const compilador = ler("compilador/compilador.lua");
const gerador = ler("compilador/gerador.lua");
const modelo = ler("plugin/_modelo_plugin.lua");

// V8.0: o modelo inclui apenas Compilador + Gerador, sem runtime interpretado.
let saida = modelo
  .replace("@@COMPILADOR@@", luaString(compilador))
  .replace("@@GERADOR@@", luaString(gerador));

const sobrando = saida.match(/@@[A-Z_]+@@/g);
if (sobrando) {
  console.error("ERRO: placeholders nao substituidos: " + [...new Set(sobrando)].join(", "));
  process.exit(1);
}

const destino = path.join(raiz, "plugin", "plugin.lua");
fs.writeFileSync(destino, saida, "utf8");

console.log("plugin/plugin.lua gerado");
console.log("  compilador.lua : " + compilador.length + " bytes");
console.log("  gerador.lua    : " + gerador.length + " bytes");
console.log("  plugin.lua     : " + saida.length + " bytes");
