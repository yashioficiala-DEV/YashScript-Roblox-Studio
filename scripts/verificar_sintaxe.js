// Verifica a SINTAXE de um arquivo Lua (gerado) usando fengari, sem executar.
// Uso:  node scripts/verificar_sintaxe.js plugin/plugin.lua [outro.lua ...]
const fs = require("fs");
const path = require("path");

const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const alvos = process.argv.slice(2);
if (alvos.length === 0) {
  console.error("uso: node scripts/verificar_sintaxe.js <arquivo.lua> [...]");
  process.exit(2);
}

let falhou = 0;

for (const rel of alvos) {
  const abs = path.resolve(rel);
  if (!fs.existsSync(abs)) {
    console.log("[ausente] " + rel);
    falhou++;
    continue;
  }
  const src = fs.readFileSync(abs, "utf8").replace(/\r\n/g, "\n");

  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  const status = lauxlib.luaL_loadbuffer(
    L,
    to_luastring(src, true),
    to_luastring("@" + path.basename(abs), true),
    null
  );

  if (status === lua.LUA_OK) {
    console.log("[ok]      " + rel + "  (" + src.length + " bytes)");
  } else {
    const msg = to_jsstring(lua.lua_tostring(L, -1)) || "erro desconhecido";
    console.log("[ERRO]    " + rel + ": " + msg);
    falhou++;
  }
}

console.log("");
console.log(falhou === 0 ? "sintaxe: tudo ok" : falhou + " arquivo(s) com erro de sintaxe");
process.exit(falhou === 0 ? 0 : 1);
