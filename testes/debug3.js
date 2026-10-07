const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;
const raiz = path.join(__dirname, "..");
const compiladorFonte = fs.readFileSync(path.join(raiz, "compilador/compilador.lua"), "utf8");
const enc = (s) => JSON.stringify(s);

const casos = [
  "quando clicar 'btn'\nfim\n",
  "quando clicar 'btn'\nmostrar texto \"x\"\nfim\n",
  "quando clicar 'btn'\nanimacao = fade in + escala = +5\nfim\n",
  "criar botao 'b'\nfim\n",
  "incluir \"x\"\n",
  "principal\n",
];

function run(nome, source) {
  process.stdout.write("[" + nome + "] ");
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_newtable(L);
  lua.lua_pushstring(L, to_luastring("compiladorFonte"));
  lua.lua_pushstring(L, to_luastring(compiladorFonte));
  lua.lua_settable(L, -3);
  lua.lua_setglobal(L, to_luastring("ENTRADA"));
  let script = `
  local ENTRADA = _G.ENTRADA
  local carregar = loadstring or load
  local c = assert(carregar(ENTRADA.compiladorFonte))()
  local ok, res = c.Compilar(${enc(source)})
  if ok then print("OK") else print("ERRO " .. tostring(res.erro)) end
  `;
  const st = lauxlib.luaL_loadstring(L, to_luastring(script));
  if (st !== lua.LUA_OK) { console.error("load err", nome); return; }
  try {
    const r = lua.lua_pcall(L, 0, 0, 0);
    if (r !== lua.LUA_OK) console.error("pcall err", lua.lua_tolstring(L, -1, 0).toString());
  } catch (e) {
    console.error("JS exception", e.message);
  }
}

for (let i = 0; i < casos.length; i++) run(i, casos[i]);