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

// carrega compilador e gerador no ambiente Lua
lua.lua_getglobal(L, luaString("ENTRADA"));
lua.lua_getfield(L, -1, luaString("compiladorFonte"));
let compFonte = lua.lua_tojsstring(L, -1);
lua.lua_pop(L, 2);

lua.lua_getglobal(L, luaString("ENTRADA"));
lua.lua_getfield(L, -1, luaString("geradorFonte"));
let gerFonte = lua.lua_tojsstring(L, -1);
lua.lua_pop(L, 2);

// Substitui 'return Compilador' por '_G.Compilador = Compilador' para expor o módulo
compFonte = compFonte.replace(/^return Compilador$/m, '_G.Compilador = Compilador');
gerFonte = gerFonte.replace(/^return Gerador$/m, '_G.Gerador = Gerador');

const compStatus = lauxlib.luaL_loadstring(L, luaString(compFonte));
if (compStatus !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao compilar compilador.lua: " + msgBuf);
}
const compResult = lua.lua_pcall(L, 0, 0, 0);
if (compResult !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao executar compilador.lua: " + msgBuf);
}

const gerStatus = lauxlib.luaL_loadstring(L, luaString(gerFonte));
if (gerStatus !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao compilar gerador.lua: " + msgBuf);
}
const gerResult = lua.lua_pcall(L, 0, 0, 0);
if (gerResult !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao executar gerador.lua: " + msgBuf);
}

// carrega rodar.lua
const fonte = ler(path.join("testes", "rodar.lua"));
const status = lauxlib.luaL_loadstring(L, luaString(fonte));
if (status !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao compilar rodar.lua: " + msgBuf);
}
// Executa rodar.lua em protected mode para capturar qualquer erro
const resultado = lua.lua_pcall(L, 0, 0, 0);
if (resultado !== lua.LUA_OK) {
  const errType = lua.lua_type(L, -1);
  let errMsg = "desconhecido";
  if (errType === 4) { // LUA_TSTRING
    errMsg = lua.lua_tojsstring(L, -1);
  } else if (errType === 5) { // LUA_TTABLE
    lua.lua_getfield(L, -1, luaString("erro"));
    const tableErr = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    if (tableErr) errMsg = tableErr;
  }
  console.error("Erro no rodar.lua:", errMsg);
}
console.log("Execução finalizada.");
