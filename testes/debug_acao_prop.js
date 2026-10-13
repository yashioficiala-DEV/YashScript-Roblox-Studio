const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;
const raiz = path.join(__dirname, "..");

const compiladorFonte = fs.readFileSync(path.join(raiz, "compilador/compilador.lua"), "utf8");
const geradorFonte = fs.readFileSync(path.join(raiz, "compilador/gerador.lua"), "utf8");
const enc = (s) => JSON.stringify(s).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");

const fonte = `usar "Titulo" = StarterGui.Menu.Titulo
usar "Botao" = StarterGui.Menu.Botao

criar acao MudarTexto
    Titulo = "oi"
fim

quando clicar "Botao"
    executar acao MudarTexto
fim
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
lua.lua_pushstring(L, to_luastring("compiladorFonte"));
lua.lua_pushstring(L, to_luastring(compiladorFonte));
lua.lua_settable(L, -3);
lua.lua_pushstring(L, to_luastring("geradorFonte"));
lua.lua_pushstring(L, to_luastring(geradorFonte));
lua.lua_settable(L, -3);
lua.lua_setglobal(L, to_luastring("ENTRADA"));

const script = `
local ENTRADA = _G.ENTRADA
local carregar = loadstring or load
local compilador = assert(carregar(ENTRADA.compiladorFonte))()
local gerador = assert(carregar(ENTRADA.geradorFonte))()
local ok, res = compilador.Compilar(${enc(fonte)})
if not ok then
  print("ERRO COMPILAR: " .. tostring(res.erro) .. " linha " .. tostring(res.linha))
  return
end
print("--- programa compilado OK ---")
for _, ctx in ipairs({ "servidor", "cliente" }) do
  local gok, luau = gerador.GerarLuau(res, { contexto = ctx })
  if not gok then
    print("[contexto=" .. ctx .. "] ERRO GERAR: " .. tostring(luau.erro) .. " linha " .. tostring(luau.linha))
  else
    print("[contexto=" .. ctx .. "] OK")
    print(luau)
  end
end
`;

const st = lauxlib.luaL_loadstring(L, to_luastring(script));
if (st !== lua.LUA_OK) { console.error("load err"); process.exit(1); }
const r = lua.lua_pcall(L, 0, 0, 0);
if (r !== lua.LUA_OK) {
  console.error("pcall err:", lua.lua_tolstring(L, -1, 0).toString());
}