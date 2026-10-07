// Roda testes/plugin_modo_jogo.lua via fengari (VM Lua no Node).
// Uso:  cd C:\Users\yashi\Documents\YashScript  &&  node testes/rodar_modo_jogo.js
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

const entrada = {
  compiladorFonte: ler(path.join("compilador", "compilador.lua")),
  geradorFonte: ler(path.join("compilador", "gerador.lua")),
  arquivos: {
    ["jogo.yash"]: ler(path.join("testes", "exemplos", "jogo.yash")),
    ["main.yash"]: ler(path.join("testes", "exemplos", "main.yash")),
    ["visual.yash"]: ler(path.join("testes", "exemplos", "visual.yash")),
  },
};

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_newtable(L);
for (const [k, v] of Object.entries(entrada)) {
  lua.lua_pushstring(L, luaString(k));
  if (typeof v === "string") {
    lua.lua_pushstring(L, luaString(v));
  } else {
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

const fonte = ler(path.join("testes", "plugin_modo_jogo.lua"));
const status = lauxlib.luaL_loadstring(L, luaString(fonte));
if (status !== lua.LUA_OK) {
  throw new Error("erro ao compilar plugin_modo_jogo.lua");
}
const resultado = lua.lua_pcall(L, 0, 0, 0);
if (resultado !== lua.LUA_OK) {
  const msgBuf = lua.lua_tolstring(L, -1, 0);
  throw new Error("erro ao executar plugin_modo_jogo.lua: " + msgBuf);
}
