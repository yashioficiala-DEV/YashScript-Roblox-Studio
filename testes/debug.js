const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;

const raiz = path.join(__dirname, "..");
function ler(rel) { return fs.readFileSync(path.join(raiz, rel), "utf8"); }

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_newtable(L);
lua.lua_pushstring(L, to_luastring("compiladorFonte"));
lua.lua_pushstring(L, to_luastring(ler("compilador/compilador.lua")));
lua.lua_settable(L, -3);
lua.lua_setglobal(L, to_luastring("ENTRADA"));

const script = `
local ENTRADA = _G.ENTRADA
local carregar = loadstring or load
local f = assert(carregar(ENTRADA.compiladorFonte))
local c = f()
print("compilador carregado: " .. tostring(c.VERSAO))
local ok, res = c.Compilar("principal\\n")
print("compile ok:", tostring(ok))
if ok then
  print("config.principal = " .. tostring(res.principal))
else
  print("erro:", tostring(res.erro), "linha", tostring(res.linha))
end
`;
const st = lauxlib.luaL_loadstring(L, to_luastring(script));
if (st !== lua.LUA_OK) { console.error("load err"); process.exit(1); }
const r = lua.lua_pcall(L, 0, 0, 0);
if (r !== lua.LUA_OK) {
  console.error("pcall err:", lua.lua_tolstring(L, -1, 0) ? lua.lua_tolstring(L, -1, 0).toString() : "?");
}