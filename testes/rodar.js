// Bootstrap: roda os testes do compilador YashScript usando fengari (VM Lua no Node).
// Uso:  cd C:\Users\yashi\Documents\YashScript  &&  node testes/rodar.js
const fs = require("fs");
const path = require("path");

const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;

const raiz = path.join(__dirname, "..");

function ler(rel) {
  return fs.readFileSync(path.join(raiz, rel), "utf8");
}

function luaString(s) {
  return to_luastring(s);
}

// monta a tabela ENTRADA que o rodar.lua consome
const entrada = {
  compiladorFonte: ler(path.join("compilador", "compilador.lua")),
  geradorFonte: ler(path.join("compilador", "gerador.lua")),
  fonteFuncoes: ler(path.join("LOGS", "funcoes.yash")),
  fonteColecoes: ler(path.join("LOGS", "colecoes.yash")),
  fonteRepeticoes: ler(path.join("LOGS", "repeticoes.yash")),
  fonteContinue: ler(path.join("LOGS", "continue.yash")),
  fonteCondicionais: ler(path.join("LOGS", "condicionais.yash")),
  fonteEscoposFuncao: ler(path.join("LOGS", "escopos_funcao.yash")),
  fonteEscoposEvento: ler(path.join("LOGS", "escopos_evento.yash")),
  fonteRetornoTemporizador: ler(path.join("LOGS", "retorno_temporizador.yash")),
  fontePrincipal: ler(path.join("testes", "exemplos", "main.yash")),
  arquivos: {
    ["visual.yash"]: ler(path.join("testes", "exemplos", "visual.yash")),
  },
};

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// cria a tabela global ENTRADA
lua.lua_newtable(L);
for (const [k, v] of Object.entries(entrada)) {
  lua.lua_pushstring(L, luaString(k));
  if (typeof v === "string") {
    lua.lua_pushstring(L, luaString(v));
  } else if (typeof v === "object") {
    lua.lua_newtable(L);
    for (const [k2, v2] of Object.entries(v)) {
      lua.lua_pushstring(L, luaString(k2));
      lua.lua_pushstring(L, luaString(v2));
      lua.lua_settable(L, -3);
    }
  }
  lua.lua_settable(L, -3);
}
lua.lua_setglobal(L, luaString("ENTRADA"));

// carrega e executa rodar.lua
const fonte = ler(path.join("testes", "rodar.lua"));
const status = lauxlib.luaL_loadstring(L, luaString(fonte));
if (status !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao compilar rodar.lua: " + msgBuf);
}
const resultado = lua.lua_pcall(L, 0, 0, 0);
if (resultado !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao executar rodar.lua: " + msgBuf);
}
