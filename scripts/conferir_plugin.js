// Confere o artefato empacotado (plugin/plugin.lua):
//   1. o artefato inteiro compila como chunk Lua;
//   2. as duas fontes embutidas (Compilador, Gerador) são
//      exatamente os arquivos do repositório, depois de JSONDecode;
//   3. cada uma compila sozinha.
//
// É o espelho do que o Studio faz: HttpService:JSONDecode(literal) -> fonte,
// e loadstring(fonte). Não tenta rodar a UI, que precisa de globals do Roblox
// (Color3, Instance, plugin:CreateToolbar).
const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

// o segundo argumento = true significa UTF-8; sem ele os acentos viram lixo
const s = (t) => to_luastring(t, true);
const ler = (rel) => fs.readFileSync(path.join(__dirname, "..", rel), "utf8").replace(/\r\n/g, "\n");

const artefato = ler("plugin/plugin.lua");

const ESPERADO = [
  ["Compilador", "compilador/compilador.lua"],
  ["Gerador", "compilador/gerador.lua"],
];

// 1) sintaxe do artefato inteiro
{
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const st = lauxlib.luaL_loadstring(L, s(artefato));
  if (st !== lua.LUA_OK) {
    throw new Error("plugin.lua nao compila: " + to_jsstring(lua.lua_tostring(L, -1), true));
  }
  console.log("ok: artefato compila (" + artefato.length + " bytes)");
}

// 2) as fontes embutidas: mesmo caminho do plugin, HTTPService:JSONDecode
//
// o empacotador escreve o JSON como literal Lua, então o padrão precisa
// respeitar os escapes do literal: \" e \\ não fecham a string.
const LITERAL = /HttpService:JSONDecode\(("(?:[^"\\]|\\.)*")\)/g;
const achados = [...artefato.matchAll(LITERAL)];

if (achados.length !== ESPERADO.length) {
  throw new Error(
    "esperado " + ESPERADO.length + " fontes embutidas, achei " + achados.length +
    " (o modelo declara FONTES com Compilador e Gerador?)"
  );
}

const relatorio = [];
for (let i = 0; i < achados.length; i++) {
  const [nome, rel] = ESPERADO[i];
  const literal = achados[i][1];

  // o empacotador escapa o JSON para caber num literal Lua (\\ e \"),
  // então primeiro desfazemos essa camada
  const corpo = literal.slice(1, -1);
  const json = corpo.replace(/\\\\/g, "\\").replace(/\\"/g, '"');

  let fonte;
  try {
    fonte = JSON.parse(json);
  } catch (e) {
    throw new Error(nome + ": JSONDecode falhou (" + e.message + ")");
  }

  const referencia = ler(rel);
  if (fonte !== referencia) {
    throw new Error(
      nome + ": a fonte embutida difere de " + rel +
      " (embutido " + fonte.length + " bytes, arquivo " + referencia.length + ")"
    );
  }

  // 3) a fonte embutida compila sozinha
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const st = lauxlib.luaL_loadstring(L, s(fonte));
  if (st !== lua.LUA_OK) {
    throw new Error(nome + ": a fonte embutida nao compila: " + to_jsstring(lua.lua_tostring(L, -1), true));
  }

  relatorio.push("  " + nome.padEnd(10) + rel.padEnd(28) + String(fonte.length).padStart(6) + " bytes  ok");
}

console.log("ok: as " + achados.length + " fontes embutidas conferem com o repositorio e carregam");
relatorio.forEach((l) => console.log(l));
