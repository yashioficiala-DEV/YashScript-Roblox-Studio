const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;
const raiz = path.join(__dirname, "..");

const compiladorFonte = fs.readFileSync(path.join(raiz, "compilador/compilador.lua"), "utf8");
const geradorFonte = fs.readFileSync(path.join(raiz, "compilador/gerador.lua"), "utf8");
const enc = (s) => JSON.stringify(s).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");

const fonte = `usar "Jogar" = StarterGui.Menu.Jogar
usar "Fundo" = StarterGui.Menu.Fundo
usar "Menu" = StarterGui.Menu

usar "Camera" = workspace.CurrentCamera
usar "PontoDaCamera" = workspace.CameraPart

Camera.CameraType = "Scriptable"
Camera.CFrame = PontoDaCamera.CFrame

quando clicar "Jogar"
    Camera.CameraType = "Custom"
fim

quando mouse_em "Jogar"
	animar("Jogar") crescer + duracao = 0.5
fim

quando mouse_sair "Jogar"
	animar("Jogar") diminuir + duracao = 0.5
fim

quando clicar "Jogar"
	print("oi")
	animar("Jogar") fade out + duracao = 1
	animar("Fundo") fade out + duracao = 1
	esperar 1
	Menu.Enabled = falso
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
local gok, luau = gerador.GerarLuau(res, { contexto = "servidor" })
if not gok then
  print("ERRO GERAR: " .. tostring(luau.erro) .. " linha " .. tostring(luau.linha))
  return
end
print(luau)
`;

const st = lauxlib.luaL_loadstring(L, to_luastring(script));
if (st !== lua.LUA_OK) { console.error("load err"); process.exit(1); }
const r = lua.lua_pcall(L, 0, 0, 0);
if (r !== lua.LUA_OK) {
  console.error("pcall err:", lua.lua_tolstring(L, -1, 0).toString());
}