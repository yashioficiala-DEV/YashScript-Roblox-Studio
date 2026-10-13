const f = require('fengari');
const {lua, lauxlib, lualib, to_luastring} = f;
const fs = require('fs');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

let c = fs.readFileSync('compilador/compilador.lua', 'utf8');
lauxlib.luaL_loadstring(L, to_luastring(c));
lua.lua_pcall(L, 0, 0, 0);

lua.lua_getglobal(L, to_luastring('Compilador'));
lua.lua_getfield(L, -1, to_luastring('Compilar'));
lua.lua_pushstring(L, to_luastring("proibir clique 'x' de mostrar(Chat)"));
lua.lua_newtable(L);
const s = lua.lua_pcall(L, 2, 2, 0);

console.log('pcall status:', s);
console.log('ok:', lua.lua_toboolean(L, -2));
if (!lua.lua_toboolean(L, -2)) {
  lua.lua_getfield(L, -1, to_luastring('erro'));
  console.log('err:', lua.lua_tojsstring(L, -1));
  lua.lua_pop(L, 1);
  lua.lua_getfield(L, -3, to_luastring('linha'));
  console.log('linha:', lua.lua_tonumber(L, -1));
}